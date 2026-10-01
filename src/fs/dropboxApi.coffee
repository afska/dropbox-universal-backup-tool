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

	readDir: (path, tail, retries = 0) =>
		path = normalizePath(path).replace /\/+$/, ""

		req =
			if tail?
				@request "files/list_folder/continue", { cursor: tail.cursor }
			else
				@request "files/list_folder", { path: path, recursive: true, limit: 500 }

		req
			.catch => throw "Error reading the remote directory #{path}."
			.then (chunk) =>
				unless _.isArray(chunk?.entries) and _.isBoolean(chunk.has_more) and _.isString(chunk.cursor) and chunk.cursor.length > 0
					if retries < 2
						return Promise.delay(1000).then => @readDir path, tail, retries + 1
					throw new Error("Invalid or incomplete Dropbox listing for #{path}; comparison aborted.")

				cursor = chunk.cursor
				entries = (tail?.entries || []).concat chunk.entries
				@emit "reading", entries.length

				if chunk.has_more
					@readDir path, { cursor, entries }
				else
					_(entries)
						.compact()
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
		isFolder = stats[".tag"] is "folder"

		if isFolder
			path: normalizePath(stats.path_lower).slice(path.length)
			name: stats.name
			isFolder: true
		else
			path: normalizePath(stats.path_lower).slice(path.length)
			name: stats.name
			size: stats.size
			mtime: new Date(stats.client_modified).setUTCMilliseconds 0
			content_hash: stats.content_hash

	_makeSaveOptions: (localFile, remotePath) =>
		rareISODate = new Date(localFile.mtime).toISOString().replace /\.[0-9]{3}/, ""
		# (without milliseconds)

		path: remotePath
		mode: "overwrite"
		client_modified: rareISODate
		mute: true
