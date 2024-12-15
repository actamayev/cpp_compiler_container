// src/server.ts
import express, { Request, Response } from "express"
import { promisify } from "util"
import bodyParser from "body-parser"
import { exec } from "child_process"
import { createReadStream, existsSync } from "fs"

const execAsync = promisify(exec)
const app = express()
const port = 3001

app.use(bodyParser.json())

// Health check endpoint
app.get("/health", (req, res) => {
	res.json({ status: "healthy" })
})

interface CompileRequest {
    userCode: string;
    pipUUID: string;
}

app.post("/compile", compile)

async function compile(req: Request, res: Response): Promise<void> {
	try {
		const { userCode, pipUUID } = req.body as CompileRequest
		console.log(`Starting compilation for PIP: ${pipUUID}`)

		// Clean build directory but preserve PlatformIO cache
		await execAsync("rm -rf /workspace/.pio/build/*")

		// Write user code
		await execAsync(`
            mkdir -p /workspace/src && \
            echo '${userCode.replace(/'/g, "'\\''")}' > /workspace/src/user_code.cpp
        `)

		// Run compilation
		const { stdout, stderr } = await execAsync(
			"cd /workspace && PLATFORMIO_BUILD_CACHE_DIR=\"/root/.platformio/cache\" platformio run --environment staging"
		)
		console.log("Compilation output:", stdout)
		if (stderr) console.error("Compilation errors:", stderr)

		// Verify binary exists and stream it back
		const binaryPath = "/workspace/.pio/build/staging/firmware.bin"
		if (!existsSync(binaryPath)) {
			throw new Error("Binary not found after compilation")
		}

		// Set appropriate headers
		res.setHeader("Content-Type", "application/octet-stream")
		res.setHeader("Content-Disposition", `attachment; filename=${pipUUID}.bin`)

		// Stream the file directly back
		const fileStream = createReadStream(binaryPath)
		fileStream.pipe(res)

	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	} catch (error: any) {
		console.error("Compilation error:", error)
		res.status(500).json({ success: false, error: error.message })
	}
}

app.listen(port, "0.0.0.0", () => {
	console.log(`Compiler server listening on port ${port}`)
})
