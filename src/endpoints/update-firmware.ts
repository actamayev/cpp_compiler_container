/* eslint-disable security/detect-non-literal-fs-filename */
import path from "path"
import { rmSync } from "fs"
import { promisify } from "util"
import { exec } from "child_process"
import { Request, Response } from "express"
import { mkdir, writeFile, access } from "fs/promises"
import type { RestEndpointMethodTypes } from "@octokit/plugin-rest-endpoint-methods"

type GithubBranches = "main" | "staging"

const execAsync = promisify(exec)

// eslint-disable-next-line @typescript-eslint/explicit-function-return-type
const initOctokit = async () => {
	// eslint-disable-next-line @typescript-eslint/naming-convention
	const { Octokit } = await import("@octokit/rest")
	const { createAppAuth } = await import("@octokit/auth-app")

	return new Octokit({
	  authStrategy: createAppAuth,
	  auth: {
			appId: process.env.GITHUB_APP_ID,
			privateKey: process.env.GITHUB_APP_PRIVATE_KEY,
			installationId: process.env.GITHUB_INSTALLATION_ID
	  }
	})
}

type GitHubContent = RestEndpointMethodTypes["repos"]["getContent"]["response"]["data"];

async function getFileContent(owner: string, repo: string, repoPath: string, ref: string): Promise<GitHubContent> {
	try {
		const octokit = await initOctokit()

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

	// Check if contents is an array (directory listing)
	if (!Array.isArray(contents)) {
		throw new Error(`Expected directory contents for path: ${dirPath}`)
	}

	for (const item of contents) {
		const fullPath = path.join(targetPath, item.name)

		if (item.type === "dir") {
			await mkdir(fullPath, { recursive: true })
			await processDirectory(`${dirPath}/${item.name}`, fullPath, branch)
		} else if (item.type === "file") {
			const fileContent = await getFileContent("bluedotrobots", "pip-bot-firmware", item.path, branch)
			if (!("content" in fileContent)) {
				throw new Error(`No content found for file: ${item.path}`)
			}
			// GitHub API returns base64 encoded content
			const decoded = Buffer.from(fileContent.content, "base64").toString("utf8")
			await writeFile(fullPath, decoded)
		}
	}
}

async function cleanWorkspace(workspaceDir: string): Promise<void> {
	try {
		// First, try to list any processes using the directory
		await execAsync(`lsof +D ${workspaceDir}`).catch(() => {
			// If lsof fails, it likely means no processes are using the directory
			return null
		})

		// Add a small delay to allow any lingering processes to complete
		await new Promise(resolve => setTimeout(resolve, 1000))

		// Try to remove the directory
		rmSync(workspaceDir, { recursive: true, force: true })

		// Wait a moment before recreating
		await new Promise(resolve => setTimeout(resolve, 500))

		// Recreate the directory structure
		await mkdir(workspaceDir, { recursive: true })
		await mkdir(path.join(workspaceDir, "src"), { recursive: true })
	} catch (error) {
		console.error("Error during workspace cleanup:", error)
		throw new Error(`Failed to clean workspace: ${error}`)
	}
}

// eslint-disable-next-line max-lines-per-function, complexity
export default async function updateFirmware(_req: Request, res: Response): Promise<void> {
	try {
		const environment = process.env.ENVIRONMENT || "staging"
		const branch = environment === "production" ? "main" : "staging"
		const workspaceDir = process.env.WORKSPACE_BASE_DIR || "/workspace"

		console.log(`Fetching firmware from GitHub branch: ${branch} for environment: ${environment}`)

		// Clean workspace with retry logic
		let retries = 3
		while (retries > 0) {
			try {
				await cleanWorkspace(workspaceDir)
				break
			} catch (error) {
				retries--
				// eslint-disable-next-line max-depth
				if (retries === 0) {
					throw error
				}
				console.log(`Retry cleaning workspace, attempts remaining: ${retries}`)
				await new Promise(resolve => setTimeout(resolve, 2000))
			}
		}

		// Get core files
		console.log("Fetching core configuration files...")
		const coreFiles = ["platformio.ini", "partitions_custom.csv"]
		for (const file of coreFiles) {
			try {
				const content = await getFileContent("bluedotrobots", "pip-bot-firmware", file, branch)
				// eslint-disable-next-line max-depth
				if (!Array.isArray(content) && "content" in content) {
					const decoded = Buffer.from(content.content, "base64").toString("utf8")
					await writeFile(path.join(workspaceDir, file), decoded)
				} else {
					throw new Error(`Invalid content received for file ${file}`)
				}
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
