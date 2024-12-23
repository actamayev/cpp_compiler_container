import { Request, Response } from "express"
import retrieveLocalFirmware from "../utils/retrieve-local-firmware"
import retrieveFirmwareFromGithub from "../utils/retrieve-firmware-from-github"

export default async function updateFirmware(_req: Request, res: Response): Promise<void> {
	try {
		const environment = process.env.ENVIRONMENT

		if (environment === "local") {
			return await retrieveLocalFirmware(res)
		}
		await retrieveFirmwareFromGithub(res)
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
