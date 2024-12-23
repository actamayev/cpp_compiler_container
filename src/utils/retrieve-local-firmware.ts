import { promisify } from "util"
import { exec } from "child_process"
import { Response } from "express"
import { downloadAndExtractRepo } from "../utils/github-utils"

const execAsync = promisify(exec)

export default async function retrieveLocalFirmware(res: Response): Promise<void> {
	try {
		const workspaceDir = process.env.WORKSPACE_BASE_DIR || "/workspace"

		// Clean workspace with retry logic
		await execAsync(`find ${workspaceDir} -mindepth 1 -delete`)

		await downloadAndExtractRepo(
			"bluedotrobots",
			"pip-bot-firmware",
			branch,
			workspaceDir
		)

		res.json({
			success: true,
			message: "Firmware updated successfully from local repo",
			environment: "Local",
			timestamp: new Date().toISOString()
		})
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
	} catch (error: any) {
		console.error("Failed to retrieve firmware:", error)
		res.status(500).json({
			success: false,
			error: error.message,
			timestamp: new Date().toISOString()
		})
	}
}
