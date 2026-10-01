Promise = require("bluebird")
{ EventEmitter } = require("events")
fs = require("fs")
_ = require("lodash")

module.exports =

class DropboxResumableUpload extends EventEmitter
	constructor: (@localFile, @remotePath, @api) ->
		@BUFFER_SIZE = global.CHUNK_SIZE * 1024 * 1024
		@TIMEOUT = 120000

	run: (onProgress) =>
		new Promise (resolve, reject) =>
			@_initialize()

			@on "chunk-ok", (progress) ->
				onProgress progress
				@_uploadChunk()

			@on "chunk-error", ->
				@_uploadChunk true

			@on "complete", ->
				@_dispose() ; resolve()

			@on "failed", (e) ->
				@_dispose() ; reject(e)

			@_uploadChunk()

	pendingBytes: =>
		@localFile.size - @uploadedBytes

	_uploadChunk: (isRetry) =>
		cursor =
			if @sessionId?
				session_id: @sessionId, offset: @uploadedBytes
			else {}

		if @pendingBytes() > 0
			if not isRetry
				bytesToRead = @_trimChunkIfNeeded()
				try
					bytesRead = 0
					while bytesRead < bytesToRead
						count = fs.readSync @fd, @chunk, bytesRead, bytesToRead - bytesRead, null
						if count is 0 then throw new Error("Unexpected end of file: #{@localFile.path}")
						bytesRead += count
				catch e
					return @emit "failed", e

			stage = if @sessionId? then "append" else "start"
			return @api.request("files/upload_session/#{stage}", @chunk, cursor)
				.timeout @TIMEOUT
				.then (result) =>
					@sessionId = result.session_id if result?.session_id?
					@uploadedBytes += @chunk.length

					@emit "chunk-ok", @chunk.length
				.catch => @emit "chunk-error"

		@api.request("files/upload_session/finish", "", {
			cursor: cursor
			commit: @api._makeSaveOptions @localFile, @remotePath
		}).then => @emit "complete"
		.catch (e) => @emit "failed", e

	_initialize: =>
		@fd = fs.openSync @localFile.path, "r"
		if not @fd? then throw "Unable to open the file"

		@uploadedBytes = 0
		@chunk = new Buffer.alloc(@BUFFER_SIZE)
		@sessionId = null

	_trimChunkIfNeeded: =>
		chunkSize = Math.min @pendingBytes(), @BUFFER_SIZE
		if @pendingBytes() < @BUFFER_SIZE
			@chunk = @chunk.slice 0, chunkSize
		chunkSize

	_dispose: =>
		fs.closeSync @fd
