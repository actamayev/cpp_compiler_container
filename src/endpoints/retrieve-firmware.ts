/* eslint-disable security/detect-non-literal-fs-filename */
import path from "path"
import { rmSync } from "fs"
import { promisify } from "util"
import { Octokit } from "octokit"
import { exec } from "child_process"
import { Request, Response } from "express"
import { createAppAuth } from "@octokit/auth-app"
import { mkdir, writeFile, access } from "fs/promises"

type GithubBranches = "main" | "staging"

const execAsync = promisify(exec)

const octokit = new Octokit({
	authStrategy: createAppAuth,
	auth: {
	  appId: process.env.GITHUB_APP_ID,
	  privateKey: process.env.GITHUB_APP_PRIVATE_KEY,
	  installationId: process.env.GITHUB_INSTALLATION_ID
	}
})

// eslint-disable-next-line @typescript-eslint/explicit-function-return-type
async function getFileContent(owner: string, repo: string, repoPath: string, ref: string) {
	try {
		const response = await octokit.rest.repos.getContent({
			owner,
			repo,
			path: repoPath,
			ref
		})
		return response.data
	} catch (error) {
		console.error(error)
		throw error
	}
}

// Get source directory contents recursively
async function processDirectory(dirPath: string, targetPath: string, branch: GithubBranches): Promise<void> {
	const contents = await getFileContent("bluedotrobots", "pip-bot-firmware", dirPath, branch)

	for (const item of contents) {
		const fullPath = path.join(targetPath, item.name)

		if (item.type === "dir") {
			await mkdir(fullPath, { recursive: true })
			await processDirectory(`${dirPath}/${item.name}`, fullPath, branch)
		} else if (item.type === "file") {
			const content = await getFileContent("bluedotrobots", "pip-bot-firmware", item.path, branch)
			await writeFile(fullPath, content)
		}
	}
}

// eslint-disable-next-line max-lines-per-function
export default async function retrieveFirmware(req: Request, res: Response): Promise<void> {
	try {
		const environment = process.env.ENVIRONMENT || "staging"
		const branch = environment === "production" ? "main" : "staging"
		const workspaceDir = process.env.WORKSPACE_BASE_DIR || "/workspace"

		console.log(`Fetching firmware from GitHub branch: ${branch} for environment: ${environment}`)

		// Clean workspace directory
		rmSync(workspaceDir, { recursive: true, force: true })
		await mkdir(workspaceDir, { recursive: true })
		await mkdir(path.join(workspaceDir, "src"), { recursive: true })

		// Get core files
		console.log("Fetching core configuration files...")
		const coreFiles = ["platformio.ini", "partitions_custom.csv"]
		for (const file of coreFiles) {
			try {
				const content = await getFileContent("bluedotrobots", "pip-bot-firmware", file, branch)
				await writeFile(path.join(workspaceDir, file), content)
			} catch (error) {
				throw new Error(`Failed to fetch required file ${file}: ${error}`)
			}
		}

		// Get src directory
		console.log("Fetching source files...")
		await processDirectory("src", path.join(workspaceDir, "src"), branch)

		// Verify all required files exist
		for (const file of coreFiles) {
			const filePath = path.join(workspaceDir, file)
			try {
				await access(filePath)
			} catch {
				throw new Error(`Required file ${file} not found after retrieval`)
			}
		}

		console.log("Directory contents after retrieval:")
		await execAsync(`ls -la ${workspaceDir}`)
		await execAsync(`ls -la ${path.join(workspaceDir, "src")}`)

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
