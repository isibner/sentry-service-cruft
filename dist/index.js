(function() {
  var CONSTANTS, CruftService, Handlebars, _, async, child_process, fs, isTextOrBinary, moment, path, querystring, url;

  _ = require('lodash');

  Handlebars = require('handlebars');

  path = require('path');

  url = require('url');

  fs = require('fs');

  querystring = require('querystring');

  isTextOrBinary = require('istextorbinary');

  moment = require('moment');

  child_process = require('child_process');

  async = require('async');

  CONSTANTS = {
    NAME: 'cruft',
    DISPLAY_NAME: 'Cruft Tracker',
    ICON_FILE_PATH: path.join(__dirname, '../', '123.png'),
    AUTH_ENDPOINT: null
  };

  CruftService = (function() {
    function CruftService(arg) {
      var CruftTrackSchema, findOrCreate, mongoose, ref, templateString;
      this.config = arg.config, this.packages = arg.packages, this.db = arg.db, this.sourceProviders = arg.sourceProviders;
      ref = this.packages, mongoose = ref.mongoose, findOrCreate = ref['mongoose-findorcreate'];
      console.log(this.config);
      CruftTrackSchema = new mongoose.Schema({
        repoId: {
          type: String,
          required: true
        },
        userId: {
          type: String,
          required: true
        },
        sourceProviderName: {
          type: String,
          required: true
        },
        cruft: mongoose.Schema.Types.Mixed
      });
      CruftTrackSchema.plugin(findOrCreate);
      this.CruftTrackModel = mongoose.model('cruft:CruftTrackModel', CruftTrackSchema);
      templateString = fs.readFileSync(path.join(__dirname, '../template.handlebars'), 'utf8');
      this.template = Handlebars.compile(templateString);
      _.extend(this, CONSTANTS);
    }

    CruftService.prototype.isAuthenticated = function(req) {
      return true;
    };

    CruftService.prototype.initializeAuthEndpoints = function(router) {};

    CruftService.prototype.initializeOtherEndpoints = function(router) {};

    CruftService.prototype.initializePublicEndpoints = function(router) {
      router.get('/:sourceProviderName/:repoId', (function(_this) {
        return function(req, res, next) {
          var ref, repoId, sourceProviderName;
          ref = req.params, sourceProviderName = ref.sourceProviderName, repoId = ref.repoId;
          return _this.CruftTrackModel.findOne({
            sourceProviderName: sourceProviderName,
            repoId: repoId
          }, function(err, model) {
            if (err) {
              return next(err);
            }
            if (model == null) {
              return next(new Error('No cruft service has been initialized at that url.'));
            }
            res.set('Content-Type', 'text/html');
            model.cruft = _.mapValues(model.cruft, function(cruftArr) {
              return _.map(cruftArr, function(cruftItem) {
                return _.extend(cruftItem, {
                  formattedDate: moment(cruftItem.date, 'YYYY-MM-DD HH:mm:ss Z').fromNow()
                });
              });
            });
            return res.send(_this.template(model));
          });
        };
      })(this));
      return router.get('/:sourceProviderName/:repoId/data.json', (function(_this) {
        return function(req, res, next) {
          var ref, repoId, sourceProviderName;
          ref = req.params, sourceProviderName = ref.sourceProviderName, repoId = ref.repoId;
          return _this.CruftTrackModel.findOne({
            sourceProviderName: sourceProviderName,
            repoId: repoId
          }, function(err, model) {
            if (err) {
              return next(err);
            }
            if (model == null) {
              return next(new Error('No cruft service has been initialized at that url.'));
            }
            res.set('Content-Type', 'text/json');
            return res.send(model.cruft);
          });
        };
      })(this));
    };

    CruftService.prototype.activateServiceForRepo = function(repoModel, callback) {
      var repoId, sourceProviderName, userId;
      repoId = repoModel.repoId, userId = repoModel.userId, sourceProviderName = repoModel.sourceProviderName;
      return this.CruftTrackModel.findOrCreate({
        repoId: repoId,
        userId: userId,
        sourceProviderName: sourceProviderName
      }, (function(_this) {
        return function(err, model, created) {
          var successMessage;
          if (err) {
            return callback(err);
          }
          successMessage = "Cruft tracker activated! View at <a href=\"/plugins/services/" + _this.NAME + "/" + sourceProviderName + "/" + (encodeURIComponent(repoId)) + "/\">this link</a>";
          if (!created) {
            model.cruft = {};
            model.markModified('cruft');
            return model.save(function(err) {
              return callback(err, successMessage);
            });
          } else {
            return callback(null, successMessage);
          }
        };
      })(this));
    };

    CruftService.prototype._handleData = function(repoModel, files, tempPath, callback) {
      var cruft, cruftType, i, len, ref, repoId, sourceProviderName, userId;
      repoId = repoModel.repoId, userId = repoModel.userId, sourceProviderName = repoModel.sourceProviderName;
      cruft = {};
      ref = this.config.cruft;
      for (i = 0, len = ref.length; i < len; i++) {
        cruftType = ref[i];
        cruft[cruftType.name] = [];
      }
      return this.CruftTrackModel.findOne({
        repoId: repoId,
        userId: userId,
        sourceProviderName: sourceProviderName
      }, (function(_this) {
        return function(err, model) {
          var allCruft, file, j, k, l, len1, len2, len3, line, lineNumber, lines, ref1, relativeFilename;
          if (err) {
            callback(err);
          }
          for (j = 0, len1 = files.length; j < len1; j++) {
            file = files[j];
            if (isTextOrBinary.isTextSync(file, fs.readFileSync(file))) {
              relativeFilename = path.relative(tempPath, file);
              lines = fs.readFileSync(file, 'utf8').split('\n');
              for (lineNumber = k = 0, len2 = lines.length; k < len2; lineNumber = ++k) {
                line = lines[lineNumber];
                ref1 = _this.config.cruft;
                for (l = 0, len3 = ref1.length; l < len3; l++) {
                  cruftType = ref1[l];
                  if (cruftType.regex.test(line)) {
                    cruft[cruftType.name].push({
                      'lineNumber': lineNumber + 1,
                      contents: line,
                      file: relativeFilename
                    });
                  }
                }
              }
            }
          }
          allCruft = _(cruft).map(_.identity).flatten().value();
          return async.eachLimit(allCruft, 25, (function(cruftItem, cb) {
            return child_process.exec("git blame -l -L " + cruftItem.lineNumber + ",+1 -- " + cruftItem.file, {
              cwd: tempPath
            }, function(err, stdout) {
              var commitDate, committerName, importantPart;
              if (err != null) {
                cb(err);
              }
              importantPart = stdout.substring(0, stdout.indexOf(')') + 1);
              committerName = importantPart.split('(')[1].split(/[\d]{4}\-[\d]{2}\-[\d]{2}/i)[0].trim();
              commitDate = importantPart.match(/[\d]{4}\-[\d]{2}\-[\d]{2} [\d]{2}:[\d]{2}:[\d]{2} (\+|\-)?[\d]{4}/i)[0];
              cruftItem.committer = committerName;
              cruftItem.date = commitDate;
              return cb();
            });
          }), function(err) {
            if (err != null) {
              callback(err);
            }
            model.cruft = cruft;
            model.markModified('cruft');
            return model.save(callback);
          });
        };
      })(this));
    };

    CruftService.prototype.handleInitialRepoData = function(repoModel, arg, callback) {
      var files, tempPath;
      files = arg.files, tempPath = arg.tempPath;
      return this._handleData(repoModel, files, tempPath, callback);
    };

    CruftService.prototype.handleHookRepoData = function(repoModel, arg, callback) {
      var files, tempPath;
      files = arg.files, tempPath = arg.tempPath;
      return this._handleData(repoModel, files, tempPath, callback);
    };

    CruftService.prototype.deactivateServiceForRepo = function(repoModel, callback) {
      var repoId, sourceProviderName, userId;
      repoId = repoModel.repoId, userId = repoModel.userId, sourceProviderName = repoModel.sourceProviderName;
      return this.CruftTrackModel.findOneAndRemove({
        repoId: repoId,
        userId: userId,
        sourceProviderName: sourceProviderName
      }, (function(_this) {
        return function(err) {
          if (err) {
            return callback(err);
          }
          return callback(null, _this.DISPLAY_NAME + " removed successfully.");
        };
      })(this));
    };

    return CruftService;

  })();

  module.exports = CruftService;

}).call(this);
