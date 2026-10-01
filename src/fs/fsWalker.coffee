Promise = require("bluebird")
walk = require("walk")
fs = Promise.promisifyAll require("fs")
nodePath = require("path")
crypto = require("crypto")
normalizePath = require("../helpers/normalizePath")
escapeRegExp = require("lodash/escapeRegExp")

IGNORED_FILE = ".DS_Store"

module.exports = new

class FsWalker
	walk: (path, ignore = []) =>
		fs.statAsync(path)
			.catch => throw "Error reading the local directory #{path}."
			.then =>
				ignore = ignore.map (entry) =>
					pattern = escapeRegExp(entry.replace(/^\/+|\/+$/g, "")).replace /\//g, "[\\\\/]"
					new RegExp "(^|[\\\\/])#{pattern}([\\\\/]|$)"
				new Promise (resolve) =>
					files = {}
					walker = walk.walk path, followLinks: true, filters: ignore

					walker.on "file", (root, stats, next) =>
						stats = @_makeStats path, root, stats
						return next() if ignore.some((pattern) => stats.path.match(pattern))
						files[normalizePath(stats.path)] = stats if stats.name isnt IGNORED_FILE

						next()

					walker.on "end", =>
						resolve files

	contentHash: (path) =>
		new Promise (resolve, reject) =>
			hash = crypto.createHash "sha256"
			blockSize = 4 * 1024 * 1024
			stream = fs.createReadStream path, highWaterMark: blockSize
			stream.on "error", reject
			stream.on "readable", =>
				while (chunk = stream.read(blockSize))?
					hash.update crypto.createHash("sha256").update(chunk).digest()
			stream.on "end", => resolve hash.digest("hex")

	_makeStats: (path, root, stats) =>
		path: "/" + nodePath.relative(path, nodePath.join(root, stats.name)).split(nodePath.sep).join("/")
		name: stats.name
		size: stats.size
		mtime: stats.mtime.setUTCMilliseconds 0
