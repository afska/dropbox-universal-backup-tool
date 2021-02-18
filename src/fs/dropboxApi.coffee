DropboxResumableUpload = require("./dropboxResumableUpload")
Promise = require("bluebird")
{ EventEmitter } = require("events")
fs = Promise.promisifyAll require("fs")
request = Promise.promisifyAll require("request")
escapeUnicode = require("../helpers/escapeUnicode")
normalizePath = require("../helpers/normalizePath")
_ = require("lodash")

module.exports =

class DropboxApi extends EventEmitter
	constructor: (@token) ->
		@URL = "https://$type.dropboxapi.com/2"

	readDir: (path, tail) =>
		path = path.toLowerCase()

		req =
			if tail?
				@request "files/list_folder/continue", { cursor: tail.cursor }
			else
				@request "files/list_folder", { path: path, recursive: true }

		req
			.catch => throw "Error reading the remote directory #{path}."
			.then (chunk) =>
				cursor = chunk.cursor
				entries = (tail?.entries || []).concat chunk.entries
				@emit "reading", entries.length

				if chunk.has_more
					@readDir path, { cursor, entries }
				else
					_(entries)
						.map (stats) => @_makeStats path, stats, entries
						.keyBy "path"
						.mapKeys (v, k) => normalizePath k
						.value()

	uploadFile: (localFile, remotePath) =>
		if localFile.size is 0
			@request "files/upload", "", @_makeSaveOptions(localFile, remotePath)
		else
			new DropboxResumableUpload(localFile, remotePath, @)
				.run (progress) =>
					@emit "progress", { file: localFile, progress }

	deleteEntry: (path) =>
		@request "files/delete", { path }

	moveFile: (oldPath, newPath) =>
		@request "files/move",
			from_path: oldPath
			to_path: newPath

	getAccountInfo: =>
		@request "users/get_current_account"
			.catch => throw "Error retrieving the user info."

	request: (url, body, header) =>
		isBinary = header?
		header =
			if _.isEmpty header then undefined
			else escapeUnicode JSON.stringify(header)

		baseUrl = @URL.replace "$type", (if isBinary then "content" else "api")
		options =
			auth: bearer: @token
			headers:
				if isBinary
					"Content-Type": "application/octet-stream"
					"Dropbox-API-Arg": header
			url: "#{baseUrl}/#{url}"
			body: body
			json: not isBinary

		request.postAsync(options).then ({ statusCode, body }) =>
			success = /2../.test statusCode
			if not success
				throw new Error(body.error_summary || body.error || body)
			if isBinary then JSON.parse(body) else body

	_makeStats: (path, stats, entries) =>
		if stats is undefined
			console.error "ERROR: stats is undefined"
			console.log "Path:", path
			console.log "Entries:", JSON.stringify(entries, null, 2)
			process.exit 1

		isFolder = stats[".tag"] is "folder"

		if isFolder
			path: stats.path_lower.replace path, ""
			name: stats.name
			isFolder: true
		else
			path: stats.path_lower.replace path, ""
			name: stats.name
			size: stats.size
			mtime: new Date(stats.client_modified).setMilliseconds 0

	_makeSaveOptions: (localFile, remotePath) =>
		rareISODate = new Date(localFile.mtime).toISOString().replace /\.[0-9]{3}/, ""
		# (without milliseconds)

		path: remotePath
		mode: "overwrite"
		client_modified: rareISODate
		mute: true
