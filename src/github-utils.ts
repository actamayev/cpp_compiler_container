/* eslint-disable @typescript-eslint/naming-convention */
/* eslint-disable security/detect-non-literal-fs-filename */
import path from "path"
import { mkdir, writeFile } from "fs/promises"
import type { RestEndpointMethodTypes } from "@octokit/plugin-rest-endpoint-methods"
import { Readable } from "stream"

type GithubBranches = "main" | "staging"

// eslint-disable-next-line @typescript-eslint/explicit-function-return-type
const initOctokit = async () => {
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

export async function downloadAndExtractRepo(
	owner: string,
	repo: string,
	branch: string,
	workspaceDir: string
): Promise<void> {
	const { Extract } = await import("unzipper")
	const octokit = await initOctokit()

	// Get the ZIP archive
	const response = await octokit.rest.repos.downloadZipballArchive({
	  owner,
	  repo,
	  ref: branch
	})

	if (!(response.data instanceof Buffer)) {
	  throw new Error("Expected ZIP content to be a Buffer")
	}

	// Create a read stream from the buffer
	const zipStream = Readable.from(response.data)

	// Extract the ZIP contents
	await new Promise<void>((resolve, reject) => {
	  zipStream
			.pipe(Extract({ path: workspaceDir }))
			.on("close", () => resolve())
			.on("error", (err: Error) => reject(err))
	})
}
