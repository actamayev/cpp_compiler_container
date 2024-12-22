/* eslint-disable @typescript-eslint/no-explicit-any */
import * as fs from "fs"
import * as path from "path"
import { Octokit } from "@octokit/rest"
import { createAppAuth } from "@octokit/auth-app"

const initOctokit = (): InstanceType<typeof Octokit> => {
	return new Octokit({
		authStrategy: createAppAuth,
		auth: {
			appId: process.env.GITHUB_APP_ID,
			privateKey: process.env.GITHUB_APP_PRIVATE_KEY?.replace(/\\n/g, "\n"),
			installationId: process.env.GITHUB_INSTALLATION_ID
		}
	})
}

async function downloadFile(
	octokit: InstanceType<typeof Octokit>,
	owner: string,
	repo: string,
	filePath: string,
	ref: string
): Promise<Buffer> {
	const response = await octokit.rest.repos.getContent({
		owner,
		repo,
		path: filePath,
		ref,
		mediaType: {
			format: "raw"
		}
	})

	return Buffer.from(response.data as any)
}

async function listAllFiles(
	octokit: InstanceType<typeof Octokit>,
	owner: string,
	repo: string,
	filePath: string,
	ref: string
): Promise<{ path: string; type: string }[]> {
	const files: { path: string; type: string }[] = []

	const response = await octokit.rest.repos.getContent({
		owner,
		repo,
		path: filePath,
		ref
	})

	const contents = response.data as any[]
	if (!Array.isArray(contents)) {
		throw new Error("Expected array of contents")
	}

	for (const item of contents) {
		if (item.type === "dir") {
			const subFiles = await listAllFiles(octokit, owner, repo, item.path, ref)
			files.push(...subFiles)
		} else {
			files.push({ path: item.path, type: item.type })
		}
	}

	return files
}

// eslint-disable-next-line max-lines-per-function
export async function downloadAndExtractRepo(
	owner: string,
	repo: string,
	branch: string,
	workspaceDir: string
): Promise<void> {
	try {
		console.log(`Starting download of ${owner}/${repo}:${branch}`)
		const octokit = initOctokit()

		// Get list of all files in the repository
		console.log("Listing all files...")
		const files = await listAllFiles(octokit, owner, repo, "", branch)
		console.log(`Found ${files.length} files in repository:`)
		console.log(files.map(f => f.path))

		// Download and save each file
		for (const file of files) {
			console.log(`Downloading: ${file.path}`)
			const content = await downloadFile(octokit, owner, repo, file.path, branch)

			const targetPath = path.join(workspaceDir, file.path)
			const targetDir = path.dirname(targetPath)

			// Create directory if it doesn't exist
			if (!fs.existsSync(targetDir)) {
				fs.mkdirSync(targetDir, { recursive: true })
			}

			// Write file
			fs.writeFileSync(targetPath, content)
			console.log(`Saved: ${file.path}`)
		}

		console.log("Final workspace contents:")
		function listFilesRecursively(dir: string): string[] {
			const results: string[] = []
			const entries = fs.readdirSync(dir)

			for (const entry of entries) {
				const fullPath = path.join(dir, entry)
				const stat = fs.statSync(fullPath)
				const relativePath = path.relative(workspaceDir, fullPath)

				if (stat.isDirectory()) {
					results.push(`[DIR] ${relativePath}`)
					results.push(...listFilesRecursively(fullPath))
				} else {
					results.push(relativePath)
				}
			}

			return results
		}

		console.log(listFilesRecursively(workspaceDir))

	} catch (error) {
		console.error("Error downloading repository:", error)
		throw error
	}
}
