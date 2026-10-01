module.exports = (path) =>
	path.normalize("NFC").toLowerCase().normalize("NFC")
