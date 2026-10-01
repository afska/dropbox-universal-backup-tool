Cli = require("./cli")
PrettyError = require("pretty-error")
_ = require("lodash")
require("colors")

#####################
# Chunk size in MB  #
global.CHUNK_SIZE = 1
#####################

actions =
	"me": ->
		new Cli(config.checkParams "token").showInfo()
	"from": ->
		opts = config.checkParams("to", "token")

		concurrency = parseInt opts.concurrency
		if (_.isFinite(concurrency) and concurrency > 1)
			opts.concurrency = concurrency
		else
			opts.concurrency = 1

		ignore = try JSON.parse opts.ignore
		if ignore?
			if not _.isArray ignore
				console.log "option `ignore` should be an array"
				process.exit 1
			else
				opts.ignore = ignore
		else
			delete opts.ignore

		new Cli(opts).getFilesAndSync()
	"version": ->
		console.log "1.0.0"
	"help": ->
		options.showHelp()

# ------------------------------

options = require("node-getopt").create [
	["f", "from=PATH", "Local source path."]
	["t", "to=DROPBOX_PATH", "Dropbox destination path."]
	["k", "token=TOKEN", "Dropbox token."]
	["i", "ignore=PATHS", "JSON array of literal names/path segments to ignore at any depth."]
	["c", "concurrency=5", "Number of simultaneous operations."]
	["y", "yes", "Don't review changes before the sync."]
	["m", "me", "Show the user's Dropbox information."]
	["v", "version", "Display the version."]
	["h", "help", "Display this help."]
]

options.setHelp(
	"Usages:\n".cyan +
	"./dxubt.js --from=\"/home\" --to=\"/\" --token=blah [--concurrency=5] [--ignore='[\"node_modules\"]'] [--yes]\n".cyan +
	"./dxubt.js --me --token=blah\n".cyan +
	"\n" +
	"[[OPTIONS]]".white
)

config = options.parseSystem()
config.checkParams = (params...) ->
	params.forEach (property) ->
		if not config.options[property]?
			console.log "missing option #{property}"
			process.exit 1
	config.options

# ------------------------------

# handle errors more pretty
new PrettyError().start()
Error.stackTraceLimit = 3

# run the first or the default action
for option of actions
	if config.options[option]?
		actions[option]()
		return

actions.help()
