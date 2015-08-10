_ = require 'lodash'
Handlebars = require 'handlebars'
path = require 'path'
url = require 'url'
fs = require 'fs'
querystring = require 'querystring'
isTextOrBinary = require 'istextorbinary'
moment = require 'moment'
child_process = require 'child_process'
async = require 'async'

class CruftService

  @NAME: 'cruft'
  @DISPLAY_NAME: 'Cruft Tracker'
  @ICON_FILE_PATH: path.join(__dirname, '../', 'invalid-code-icon.png')
  @AUTH_ENDPOINT: null

  constructor: ({@config, @packages, @db, @sourceProviders}) ->
    {mongoose, 'mongoose-findorcreate': findOrCreate} = @packages
    @config.cruftTypes ?= []
    CruftTrackSchema = new mongoose.Schema {
      repoId: {type: String, required: true},
      userId: {type: String, required: true},
      sourceProviderName: {type: String, required: true},
      cruft: mongoose.Schema.Types.Mixed
    }
    CruftTrackSchema.plugin findOrCreate
    @CruftTrackModel = mongoose.model 'cruft:CruftTrackModel', CruftTrackSchema
    templateString = fs.readFileSync(path.join(__dirname, '../template.handlebars'), 'utf8')
    @template = Handlebars.compile(templateString)

  isAuthenticated: (req) -> true

  initializeAuthEndpoints: (router) ->

  initializeOtherEndpoints: (router) ->

  initializePublicEndpoints: (router) ->
    router.get '/:sourceProviderName/:repoId', (req, res, next) =>
      {sourceProviderName, repoId} = req.params
      @CruftTrackModel.findOne {sourceProviderName, repoId}, (err, model) =>
        return next(err) if err
        return next(new Error('No cruft service has been initialized at that url.')) if not model?
        res.set 'Content-Type', 'text/html'
        model.cruft = _.mapValues model.cruft, (cruftArr) ->
          return _.map cruftArr, (cruftItem) ->
            return _.extend cruftItem, {formattedDate: moment(cruftItem.date, 'YYYY-MM-DD HH:mm:ss Z').fromNow()}
        res.send @template(model)

    router.get '/:sourceProviderName/:repoId/data.json', (req, res, next) =>
      {sourceProviderName, repoId} = req.params
      @CruftTrackModel.findOne {sourceProviderName, repoId}, (err, model) =>
        return next(err) if err
        return next(new Error('No cruft service has been initialized at that url.')) if not model?
        res.set 'Content-Type', 'text/json'
        res.send model.cruft

  activateServiceForRepo: ({repoModel, repoConfig}, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    @CruftTrackModel.findOrCreate {repoId, userId, sourceProviderName}, (err, model, created) =>
      return callback(err) if err
      successMessage = "Cruft tracker activated! View at <a href=\"/plugins/services/#{@NAME}/#{sourceProviderName}/#{encodeURIComponent(repoId)}/\">this link</a>"
      if not created
        model.cruft = {}
        model.markModified 'cruft'
        model.save (err) ->
          callback(err, successMessage)
      else
        callback(null, successMessage)

  _handleData: ({repoModel, files, repoPath, repoConfig}, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    repoConfig ?= {}
    repoConfig.cruftTypes ?= []
    cruftTypes = @config.cruftTypes.concat(repoConfig.cruftTypes)
    try
      cruftTypes = cruftTypes.map ({name, regex}) ->
        return {name, regex} if _.isRegExp(regex)
        return {name, regex: new RegExp(regex, 'i')}
    catch e
      return callback e
    cruft = {}
    for cruftType in cruftTypes
      cruft[cruftType.name] = []
    @CruftTrackModel.findOne {repoId, userId, sourceProviderName}, (err, model) =>
      callback(err) if err
      for file in files
        if isTextOrBinary.isTextSync(file, fs.readFileSync(file))
          relativeFilename = path.relative(repoPath, file)
          lines = fs.readFileSync(file, 'utf8').split('\n')
          for line, lineNumber in lines
            for cruftType in cruftTypes
              if cruftType.regex.test(line)
                cruft[cruftType.name].push {'lineNumber': lineNumber + 1, contents: line, file: relativeFilename}
      allCruft = _(cruft).map(_.identity).flatten().value()
      async.eachLimit allCruft, 25, ((cruftItem, cb) ->
        child_process.exec "git blame -l -L #{cruftItem.lineNumber},+1 -- #{cruftItem.file}", {cwd: repoPath}, (err, stdout) ->
          cb(err) if err?
          importantPart = stdout.substring(0, stdout.indexOf(')') + 1)
          committerName = importantPart.split('(')[1].split(/[\d]{4}\-[\d]{2}\-[\d]{2}/i)[0].trim()
          commitDate = importantPart.match(/[\d]{4}\-[\d]{2}\-[\d]{2} [\d]{2}:[\d]{2}:[\d]{2} (\+|\-)?[\d]{4}/i)[0]
          cruftItem.committer = committerName
          cruftItem.date = commitDate
          cb()
      ), (err) ->
        callback(err) if err?
        model.cruft = cruft
        model.markModified 'cruft'
        model.save(callback)

  handleInitialRepoData: ({repoModel, files, repoPath, repoConfig}, callback) -> @_handleData({repoModel, files, repoPath, repoConfig}, callback)

  handleHookRepoData: ({repoModel, files, repoPath, repoConfig}, callback) -> @_handleData({repoModel, files, repoPath, repoConfig}, callback)

  deactivateServiceForRepo: ({repoModel, repoConfig}, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    @CruftTrackModel.findOneAndRemove {repoId, userId, sourceProviderName}, (err) =>
      return callback(err) if err
      callback(null, "#{@DISPLAY_NAME} removed successfully.")

module.exports = CruftService

