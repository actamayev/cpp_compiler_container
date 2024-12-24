/* eslint-disable @typescript-eslint/no-explicit-any */
import { Request, Response } from "express"
import compile from "../endpoints/compile"

export default async function warmupContainer(): Promise<void> {
	try {
		console.info("Warming up container")
		// Create mock req/res objects
		const mockReq = {
			body: {
				userCode: "delay(1000);",
				pipUUID: "12345",
				isWarmup: true
			}
		} as Request

		const mockRes = {
			json: (data: any) => {
				console.info("Container warmup result:", data)
				return mockRes
			},
			status: (code: number) => {
				console.info(`Container warmup status: ${code}`)
				return mockRes
			},
		} as unknown as Response

		await compile(mockReq, mockRes)
		console.info("Container warmed up")
	} catch (error) {
		console.error("Failed to warmup container:", error)
	}
}
