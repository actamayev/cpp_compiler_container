import * as fs from "fs"
import * as path from "path"
import { Readable } from "stream"
import { Extract } from "unzipper"
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

function listFilesRecursively(dir: string, baseDir: string = dir): string[] {
	const files: string[] = []
	const entries = fs.readdirSync(dir)

	for (const entry of entries) {
		const fullPath = path.join(dir, entry)
		const relativePath = path.relative(baseDir, fullPath)
		const stat = fs.statSync(fullPath)

		if (stat.isDirectory()) {
			files.push(`[DIR] ${relativePath}`)
			files.push(...listFilesRecursively(fullPath, baseDir))
		} else {
			files.push(relativePath)
		}
	}

	return files
}

function moveDirectoryContents(sourcePath: string, targetPath: string): void {
	const files = listFilesRecursively(sourcePath)
	console.log("Files to move:", files)

	for (const relativePath of files) {
		if (relativePath.startsWith("[DIR]")) {
			// Create directory
			const dirPath = path.join(targetPath, relativePath.slice(6))
			if (!fs.existsSync(dirPath)) {
				fs.mkdirSync(dirPath, { recursive: true })
			}
			continue
		}

		const sourceFile = path.join(sourcePath, relativePath)
		const targetFile = path.join(targetPath, relativePath)

		// Create target directory if it doesn't exist
		const targetDir = path.dirname(targetFile)
		if (!fs.existsSync(targetDir)) {
			fs.mkdirSync(targetDir, { recursive: true })
		}

		fs.renameSync(sourceFile, targetFile)
		console.log(`Moved: ${relativePath}`)
	}
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

		// Create a temporary directory for initial extraction
		const tempDir = path.join(workspaceDir, "_temp")
		if (!fs.existsSync(tempDir)) {
			fs.mkdirSync(tempDir)
		}

		// Get the ZIP archive
		console.log("Downloading ZIP archive...")
		const response = await octokit.rest.repos.downloadZipballArchive({
			owner,
			repo,
			ref: branch,
			request: {
				responseType: "arraybuffer"
			}
		})

		console.log("ZIP archive downloaded, size:", (response.data as string).length, "bytes")
		const buffer = Buffer.from(response.data as unknown as string)

		// Create a read stream from the buffer
		const zipStream = Readable.from(buffer)

		// Extract to temp directory first
		console.log("Extracting ZIP contents...")
		await new Promise<void>((resolve, reject) => {
			zipStream
				.pipe(Extract({ path: tempDir }))
				.on("close", () => resolve())
				.on("error", (err: Error) => reject(err))
		})

		// List contents of temp directory
		console.log("Temporary directory contents:")
		const tempContents = listFilesRecursively(tempDir)
		console.log(tempContents)

		// Get and verify the extracted directory
		const extractedDir = fs.readdirSync(tempDir)[0]
		if (!extractedDir) {
			throw new Error("No files found in extracted archive")
		}
		const extractedPath = path.join(tempDir, extractedDir)
		console.log("Extracted directory:", extractedPath)

		// Move all contents to workspace directory
		console.log("Moving files to workspace...")
		moveDirectoryContents(extractedPath, workspaceDir)

		// Clean up temp directory
		console.log("Cleaning up temporary directory...")
		fs.rmSync(tempDir, { recursive: true, force: true })

		console.log("Final workspace contents:")
		console.log(listFilesRecursively(workspaceDir))

	} catch (error) {
		console.error("Error downloading or extracting repository:", error)
		throw error
	}
}
