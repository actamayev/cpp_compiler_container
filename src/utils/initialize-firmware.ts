import { Request, Response } from "express"
import updateFirmware from "../endpoints/update-firmware"

export default async function initializeFirmware(): Promise<void> {
	try {
		// Create mock req/res objects
		const mockReq = {} as Request
		const mockRes = {
			json: (data: string) => {
				console.log("Firmware initialization result:", data)
			},
			status: (code: number) => ({
				json: (data: string): void => {
					console.log(`Firmware initialization failed (${code}):`, data)
				}
			})
		} as Response

		await updateFirmware(mockReq, mockRes)
	} catch (error) {
		console.error("Failed to initialize firmware:", error)
	}
}
