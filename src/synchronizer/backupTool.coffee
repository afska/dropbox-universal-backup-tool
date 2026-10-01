Promise = require("bluebird")
DropboxApi = require("../fs/dropboxApi")
{ EventEmitter } = require("events")
fsWalker = require("../fs/fsWalker")
dirComparer = require("./dirComparer")
asyncPipeline = require("../helpers/asyncPipeline")
_ = require("lodash")

module.exports =

class BackupTool extends EventEmitter
	constructor: ({ token, @from, @to, @concurrency }) ->
		@to = @to.replace /\/+$/, "" if @to?
		@dropboxApi = new DropboxApi(token)
		@dropboxApi.on "reading", (e) => @emit "reading", e
		@dropboxApi.on "progress", (e) => @emit "progress", e

	getFilesAndCompare: (from, to, ignore = []) =>
		promises =
			local: fsWalker.walk from, ignore
			remote: @dropboxApi.readDir to

		promises.remote.then =>
			if not promises.local.isResolved() then @emit "still-reading"
		.catch =>

		Promise.props(promises).then ({ local, remote }) =>
			dirComparer.compare local, remote
		.then (comparision) =>
			isModified = ([local, remote]) =>
				return true if local.size isnt remote.size or not remote.content_hash?
				fsWalker.contentHash(from + local.path).then (hash) => hash isnt remote.content_hash
			Promise.filter(comparision.modifiedFiles, isModified, { concurrency: 1 }).then (modifiedFiles) =>
				comparision.modifiedFiles = modifiedFiles
				comparision

	sync: (comparision) =>
		getActions = (group, action) =>
			comparision[group].map (file) =>
				=> action file

		cleans = getActions "emptyFolders", @_deleteEntry
		uploads = getActions "newFiles", @_uploadFile
		modifications = getActions "modifiedFiles", @_reuploadFile
		deletions = getActions "deletedFiles", @_deleteEntry
		moves = getActions "movedFiles", @_moveFile

		asyncPipeline(cleans, @concurrency).then =>
			asyncPipeline(uploads, @concurrency).then =>
				asyncPipeline(modifications, @concurrency).then =>
					asyncPipeline(deletions, @concurrency).then =>
						asyncPipeline moves

	getInfo: => @dropboxApi.getAccountInfo()

	_uploadFile: (file) =>
		localFile = _.assign _.clone(file),	path: @from + file.path
		@emit "uploading", localFile
		@dropboxApi.uploadFile(localFile, @to + file.path)
			.then => @emit "uploaded", localFile
			.catch (e) => @emit "not-uploaded", e

	_deleteEntry: (file) =>
		@emit "deleting", file

		@dropboxApi.deleteEntry @to + file.path
			.then => @emit "deleted", file
			.catch (e) => @emit "not-deleted", e

	_reuploadFile: ([local]) =>
		@_uploadFile local

	_moveFile: (file) =>
		@emit "moving", file

		@dropboxApi.moveFile(@to + file.oldPath, @to + file.newPath)
			.then => @emit "moved", file
			.catch (e) => @emit "not-moved", e
