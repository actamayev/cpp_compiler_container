import { promisify } from "util"
import { exec } from "child_process"
import { Response } from "express"
import fs from "fs"
import path from "path"

const execAsync = promisify(exec)

export default async function retrieveLocalFirmware(res: Response): Promise<void> {
	try {
		const firmwareSource = process.env.FIRMWARE_SOURCE || "/firmware"
		const workspaceDir = process.env.WORKSPACE_BASE_DIR || "/workspace"

		// Verify firmware exists in mounted volume
		if (!fs.existsSync(firmwareSource)) {
			throw new Error(`Local firmware not found at ${firmwareSource}`)
		}

		// Check for essential files
		const requiredFiles = ["platformio.ini", "partitions_custom.csv", "src/"]
		for (const file of requiredFiles) {
			const fullPath = path.join(firmwareSource, file)
			if (!fs.existsSync(fullPath)) {
				throw new Error(`Required firmware file/directory not found: ${file}`)
			}
		}

		// Clean workspace directory
		await execAsync(`rm -rf ${workspaceDir}/*`)

		// Copy files from mounted volume to workspace
		await execAsync(`cp -r ${firmwareSource}/* ${workspaceDir}/`)

		console.log("Files copied from mounted volume to workspace")

		res.json({
			success: true,
			message: "Firmware updated successfully from local repo",
			environment: "Local",
			timestamp: new Date().toISOString()
		})
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	} catch (error: any) {
		console.error("Failed to retrieve local firmware:", error)
		res.status(500).json({
			success: false,
			error: error.message,
			timestamp: new Date().toISOString()
		})
	}
}
