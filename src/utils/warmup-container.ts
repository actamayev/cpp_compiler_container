import { Request, Response } from "express"
import compile from "../endpoints/compile"

export default async function warmupContainer(): Promise<void> {
	try {
		console.info("Warming up container")
		// Create mock req/res objects
		const mockReq = {
			body: {
				userCode: "delay(1000);",
				pipUUID: "12345"
			}
		} as Request
		const mockRes = {
			json: (data: string) => {
				console.info("Container warmup result:", data)
			},
			status: (code: number) => ({
				json: (data: string): void => {
					console.info(`Container warmup failed (${code}):`, data)
				}
			})
		} as Response

		await compile(mockReq, mockRes)
		console.info("Container warmed up")
	} catch (error) {
		console.error("Failed to warmup container:", error)
	}
}
