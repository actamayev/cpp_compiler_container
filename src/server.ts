import express from "express"
import bodyParser from "body-parser"
import compile from "./endpoints/compile"
import updateFirmware from "./endpoints/update-firmware"
import initializeFirmware from "./utils/initialize-firmware"

const app = express()

app.use((req, res, next) => {
	res.header("Access-Control-Allow-Origin", "*")
	res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	res.header("Access-Control-Allow-Headers", "Content-Type")
	next()
})

app.use(bodyParser.json())

// Health check endpoint
app.get("/health", (req, res) => {
	console.log("Health check requested from:", req.ip)
	res.json({
		status: "healthy",
		timestamp: new Date().toISOString(),
		serverPort: process.env.SERVER_PORT,
		environment: process.env.ENVIRONMENT || "unknown"
	})
})

app.post("/compile", compile)
app.post("/update-firmware", updateFirmware)


app.listen(Number(process.env.SERVER_PORT), "0.0.0.0", async () => {
	console.log(`Compiler server listening at http://0.0.0.0:${process.env.SERVER_PORT}`)
	console.log(`Environment: ${process.env.ENVIRONMENT || "unknown"}`)

	// Initialize firmware after server starts
	await initializeFirmware()
})
