
import path from "path"
import * as fs from "fs"
import { promisify } from "util"
import { exec } from "child_process"
import { Request, Response } from "express"
import { mkdir, writeFile, access } from "fs/promises"
import { downloadAndExtractRepo } from "../github-utils"

const execAsync = promisify(exec)

export default async function updateFirmware(_req: Request, res: Response): Promise<void> {
	try {
		const environment = process.env.ENVIRONMENT || "staging"
		const branch = environment === "production" ? "main" : "staging"
		const workspaceDir = process.env.WORKSPACE_BASE_DIR || "/workspace"

		console.log(`Fetching firmware from GitHub branch: ${branch} for environment: ${environment}`)

		// Clean workspace with retry logic
		await execAsync(`find ${workspaceDir} -mindepth 1 -delete`)

		await downloadAndExtractRepo(
			"bluedotrobots",
			"pip-bot-firmware",
			branch,
			workspaceDir
		)

		// Get core files
		// console.log("Fetching core configuration files...")
		// const coreFiles = ["platformio.ini", "partitions_custom.csv"]
		// for (const file of coreFiles) {
		// 	try {
		// 		const content = await getFileContent("bluedotrobots", "pip-bot-firmware", file, branch)
		// 		// eslint-disable-next-line max-depth
		// 		if (!Array.isArray(content) && "content" in content) {
		// 			const decoded = Buffer.from(content.content, "base64").toString("utf8")
		// 			await writeFile(path.join(workspaceDir, file), decoded)
		// 		} else {
		// 			throw new Error(`Invalid content received for file ${file}`)
		// 		}
		// 	} catch (error) {
		// 		throw new Error(`Failed to fetch required file ${file}: ${error}`)
		// 	}
		// }

		// // Get src directory
		// console.log("Fetching source files...")
		// await processDirectory("src", path.join(workspaceDir, "src"), branch)

		// // Verify all required files exist
		// for (const file of coreFiles) {
		// 	const filePath = path.join(workspaceDir, file)
		// 	try {
		// 		await access(filePath)
		// 	} catch {
		// 		throw new Error(`Required file ${file} not found after retrieval`)
		// 	}
		// }

		// console.log("Directory contents after retrieval:")
		// await execAsync(`ls -la ${workspaceDir}`)
		// await execAsync(`ls -la ${path.join(workspaceDir, "src")}`)

		res.json({
			success: true,
			message: `Firmware updated successfully from ${branch} branch`,
			environment,
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
