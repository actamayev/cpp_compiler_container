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

export async function downloadAndExtractRepo(
	owner: string,
	repo: string,
	branch: string,
	workspaceDir: string
): Promise<void> {
	try {
		const octokit = initOctokit()

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

		// Extract the ZIP contents
		await new Promise<void>((resolve, reject) => {
			zipStream
				.pipe(Extract({ path: workspaceDir }))
				.on("close", () => resolve())
				.on("error", (err: Error) => reject(err))
		})
	} catch (error) {
		console.error(error)
		throw error
	}
}
