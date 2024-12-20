/* eslint-disable security/detect-non-literal-fs-filename */
import * as fs from "fs"
import * as path from "path"
import { Readable } from "stream"
import { Extract } from "unzipper"
import { Octokit } from "@octokit/rest"
import { createAppAuth } from "@octokit/auth-app"

// eslint-disable-next-line @typescript-eslint/explicit-function-return-type
const initOctokit = () => {
	return new Octokit({
		authStrategy: createAppAuth,
		auth: {
			appId: process.env.GITHUB_APP_ID,
			// eslint-disable-next-line @typescript-eslint/no-non-null-assertion
			privateKey: process.env.GITHUB_APP_PRIVATE_KEY!.replace(/\\n/g, "\n"),
			installationId: process.env.GITHUB_INSTALLATION_ID
		}
	})
}

// eslint-disable-next-line max-lines-per-function
export async function downloadAndExtractRepo(
	owner: string,
	repo: string,
	branch: string,
	workspaceDir: string
): Promise<void> {
	try {
		const octokit = initOctokit()

		// Create a temporary directory for initial extraction
		const tempDir = path.join(workspaceDir, "_temp")
		if (!fs.existsSync(tempDir)) {
			fs.mkdirSync(tempDir)
		}

		// Get the ZIP archive
		const response = await octokit.rest.repos.downloadZipballArchive({
			owner,
			repo,
			ref: branch,
			request: {
				responseType: "arraybuffer"
			}
		})

		const buffer = Buffer.from(response.data as unknown as string)

		// Create a read stream from the buffer
		const zipStream = Readable.from(buffer)

		// Extract to temp directory first
		await new Promise<void>((resolve, reject) => {
			zipStream
				.pipe(Extract({ path: tempDir }))
				.on("close", () => resolve())
				.on("error", (err: Error) => reject(err))
		})

		// Move contents from the extracted directory to workspace
		const extractedDir = fs.readdirSync(tempDir)[0] // Get the name of the extracted directory
		const extractedPath = path.join(tempDir, extractedDir)

		// Move all contents to workspace directory
		const files = fs.readdirSync(extractedPath)
		for (const file of files) {
			const srcPath = path.join(extractedPath, file)
			const destPath = path.join(workspaceDir, file)
			fs.renameSync(srcPath, destPath)
		}

		// Clean up temp directory
		fs.rmSync(tempDir, { recursive: true, force: true })

	} catch (error) {
		console.error("Error downloading or extracting repository:", error)
		throw error
	}
}
