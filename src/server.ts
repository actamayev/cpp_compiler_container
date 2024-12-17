/* eslint-disable security/detect-non-literal-fs-filename */
import express, { Request, Response } from "express"
import { promisify } from "util"
import bodyParser from "body-parser"
import { exec } from "child_process"
import { createReadStream, existsSync } from "fs"

const execAsync = promisify(exec)
const app = express()
const port = 3001

app.use((req, res, next) => {
	res.header("Access-Control-Allow-Origin", "*")
	res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	res.header("Access-Control-Allow-Headers", "Content-Type")
	next()
})

app.use(bodyParser.json())

// Health check endpoint
app.get("/health", (req, res) => {
	console.log("Health check requested from:", req.ip)
	res.json({
		status: "healthy",
		timestamp: new Date().toISOString(),
		serverPort: port,
		environment: process.env.ENVIRONMENT || "unknown"
	})
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

		process.env.USER_CODE = userCode
		process.env.PIP_ID = pipUUID
		process.env.WARMUP = "false"

		await execAsync("rm -rf /workspace/.pio/build/*")

		const { stdout, stderr } = await execAsync("/app/entrypoint.sh")

		console.log("Entrypoint output:", stdout)
		if (stderr) console.error("Entrypoint errors:", stderr)

		// Verify binary exists and stream it back
		const binaryPath = `/workspace/.pio/build/${process.env.ENVIRONMENT}/firmware.bin`
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
	console.log(`Compiler server listening at http://0.0.0.0:${port}`)
	console.log(`Environment: ${process.env.ENVIRONMENT || "unknown"}`)
})
