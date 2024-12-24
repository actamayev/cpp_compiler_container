import { promisify } from "util"
import { exec } from "child_process"
import { Request, Response } from "express"
import { createReadStream, existsSync } from "fs"

const execAsync = promisify(exec)
interface CompileRequest {
    userCode: string
    pipUUID: string
    isWarmup?: boolean
}

export default async function compile(req: Request, res: Response): Promise<void> {
	try {
		const { userCode, pipUUID, isWarmup = false } = req.body as CompileRequest
		console.info(`Starting compilation for PIP: ${pipUUID}`)

		process.env.USER_CODE = userCode
		process.env.PIP_ID = pipUUID

		await execAsync("rm -rf /workspace/.pio/build/*")

		const { stdout, stderr } = await execAsync("/app/entrypoint.sh", {
			maxBuffer: 5 * 1024 * 1024
		})

		console.info("Entrypoint output:", stdout)
		if (stderr) console.error("Entrypoint errors:", stderr)

		// Verify binary exists and stream it back
		const binaryPath = `/workspace/.pio/build/${process.env.ENVIRONMENT}/firmware.bin`
		if (!existsSync(binaryPath)) {
			throw new Error("Binary not found after compilation")
		}

		if (isWarmup) {
			// For warmup, just return success
			res.json({ success: true, message: "Warmup compilation successful" })
			return
		}

		// Set appropriate headers
		res.setHeader("Content-Type", "application/octet-stream")
		res.setHeader("Content-Disposition", `attachment; filename=${pipUUID}.bin`)

		// Stream the file directly back
		const fileStream = createReadStream(binaryPath)
		fileStream.pipe(res)
		console.info("Compilation and filestream finished")
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	} catch (error: any) {
		console.error("Compilation error:", error)
		res.status(500).json({ success: false, error: error.message })
	}
}
