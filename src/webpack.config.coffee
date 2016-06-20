# SageMathCloud, by SageMath, Inc., (c) 2016 -- License: GPLv3

###
# Webpack configuration file

Run dev server with source maps:

    npm run webpack-watch

Then visit (say)

    https://dev0.sagemath.com/

or for smc-in-smc project, info.py URL, e.g.

    https://cloud.sagemath.com/14eed217-2d3c-4975-a381-b69edcb40e0e/port/56754/

This is far from ready to use yet, e.g., we need to properly serve primus websockets, etc.:

    webpack-dev-server --port=9000 -d

Resources for learning webpack:

    - https://github.com/petehunt/webpack-howto
    - http://webpack.github.io/docs/tutorials/getting-started/

---

## Information for developers

This webpack config file might look scary, but it only consists of a few moving parts.

1. There is the "main" SMC application, which is split into "css", "lib" and "smc":
   1. css: a collection of all static styles from various locations. It might be possible
      to use the text extraction plugin to make this a .css file, but that didn't work out.
      Some css is inserted, but it doesn't work and no styles are applied. In the end,
      it doesn't matter to load it one way or the other. Furthermore, as .js is even better,
      because the initial page load is instant and doesn't require to get the compiled css styles.
   2. lib: this is a compilation of the essential js files in webapp-lib (via webapp-lib.coffee)
   3. smc: the core smc library. besides this, there are also chunks ([number]-hash.js) that are
      loaded later on demand (read up on `require.ensure`).
      For example, such a chunkfile contains latex completions, the data for the wizard, etc.
2. There are static html files for the policies.
   The policy files originate in webapp-lib/policies, where at least one file is generated by update_react_static.
   That script runs part of the smc application in node.js to render to html.
   Then, that html output is included into the html page and compiled.
   It's not possible to automate this fully, because during the processing of these templates,
   the "css" chunk from point 1.1 above is injected, too.
   In the future, also other elements from the website (e.g. <Footer/>) will be rendered as
   separate static html template elements and included there.
3. There are auxiliary files for the "video chat" functionality. That might be redone differently, but
   for now rendering to html only works via the html webpack plugin in such a way,
   that it rewrites paths and post processes the files correctly to work.

The remaining configuration deals with setting up variables (misc_node contains the centralized
information about where the page is getting rendered to, because also the hub.coffee needs to know
about certain file locations)

Development vs. Production: There are two variables DEVMODE and PRODMODE.
* Prodmode:
  * additional compression is enabled (do *not* add the -p switch to webpack, that's done here explicitly!)
  * all output filenames, except for the essential .html files, do have hashes and a rather flat hierarchy.
* Devmode:
  * Apply as little additional plugins as possible (compiles faster).
  * File names have no hashes, or hashes are deterministically based on the content.
    This means, when running webpack-watch, you do not end up with a growing pile of
    thousands of files in the output directory.

MathJax: It lives in its own isolated world. This means, don't mess with the MathJax.js ...
It needs to know from where it is loaded (the path in the URL), to retrieve many additional files on demand.
That's also the main reason why it is slow, because for each file a new SSL connection has to be setup!
(unless, http/2 or spdy do https pipelining).
How do we help MathJax a little bit by caching it, when the file names aren't hashed?
The trick is to add the MathJax version number to the path, such that it is unique and will definitely
trigger a reload after an update of MathJax.
The MathjaxVersionedSymlink below (in combination with misc_node.MATHJAX_LIB)
does extract the MathJax version number, computes the path, and symlinks to its location.
Why in misc_node? The problem is, that also the jupyter server (in its isolated iframe),
needs to know about the MathJax URL.
That way, the hub can send down the URL to the jupyter server (there is no webapp client in between).
###

'use strict'

_             = require('lodash')
webpack       = require('webpack')
path          = require('path')
fs            = require('fs')
glob          = require('glob')
child_process = require('child_process')
misc_node     = require('smc-util-node/misc_node')
async         = require('async')

SMC_VERSION   = require('smc-util/smc-version').version

git_head      = child_process.execSync("git rev-parse HEAD")
GIT_REV       = git_head.toString().trim()
TITLE         = 'SageMathCloud'
SMC_REPO      = 'https://github.com/sagemathinc/smc'
SMC_LICENSE   = 'GPLv3'
WEBAPP_LIB    = misc_node.WEBAPP_LIB
INPUT         = path.resolve(__dirname, WEBAPP_LIB)
OUTPUT        = misc_node.OUTPUT_DIR
DEVEL         = "development"
NODE_ENV      = process.env.NODE_ENV || DEVEL
PRODMODE      = NODE_ENV != DEVEL
DEVMODE       = not PRODMODE
SOURCE_MAP    = !! process.env.SOURCE_MAP
date          = new Date()
BUILD_DATE    = date.toISOString()
BUILD_TS      = date.getTime()
GOOGLE_ANALYTICS = misc_node.GOOGLE_ANALYTICS

# create a file base_url to set a base url
BASE_URL      = misc_node.BASE_URL
console.log "SMC_VERSION      = #{SMC_VERSION}"
console.log "SMC_GIT_REV      = #{GIT_REV}"
console.log "NODE_ENV         = #{NODE_ENV}"
console.log "BASE_URL         = #{BASE_URL}"
console.log "INPUT            = #{INPUT}"
console.log "OUTPUT           = #{OUTPUT}"
console.log "GOOGLE_ANALYTICS = #{GOOGLE_ANALYTICS}"

# mathjax version → symlink with version info from package.json/version
MATHJAX_URL    = misc_node.MATHJAX_URL  # from where the files are served
MATHJAX_ROOT   = misc_node.MATHJAX_ROOT # where the symlink originates
MATHJAX_LIB    = misc_node.MATHJAX_LIB  # where the symlink points to
console.log "MATHJAX_URL  = #{MATHJAX_URL}"
console.log "MATHJAX_ROOT = #{MATHJAX_ROOT}"
console.log "MATHJAX_LIB  = #{MATHJAX_LIB}"

banner = new webpack.BannerPlugin(
                        """\
                        This file is part of #{TITLE}.
                        It was compiled #{BUILD_DATE} at revision #{GIT_REV} and version #{SMC_VERSION}.
                        See #{SMC_REPO} for its #{SMC_LICENSE} code.
                        """)

# webpack plugin to do the linking after it's "done"
class MathjaxVersionedSymlink
    apply: (compiler) ->
        # make absolute path to the mathjax lib (lives in node_module of smc-webapp)
        symto = path.resolve(__dirname, "#{MATHJAX_LIB}")
        console.log("mathjax symlink: pointing to #{symto}")
        mksymlink = (dir, cb) ->
            fs.exists dir,  (exists, cb) ->
                if not exists
                    fs.symlink(symto, dir, cb)
        compiler.plugin "done", (compilation, cb) ->
            async.concat([MATHJAX_ROOT, misc_node.MATHJAX_NOVERS], mksymlink, -> cb())

mathjaxVersionedSymlink = new MathjaxVersionedSymlink()

# deterministic hashing for assets
# TODO this sha-hash lib sometimes crashes. switch to https://github.com/erm0l0v/webpack-md5-hash and try if that works!
#WebpackSHAHash = require('webpack-sha-hash')
#webpackSHAHash = new WebpackSHAHash()

# cleanup like "make distclean"
# otherwise, compiles create an evergrowing pile of files
CleanWebpackPlugin = require('clean-webpack-plugin')
cleanWebpackPlugin = new CleanWebpackPlugin [OUTPUT],
                                            verbose: true
                                            dry: false

# assets.json file
AssetsPlugin = require('assets-webpack-plugin')
assetsPlugin = new AssetsPlugin
                        filename   : path.join(OUTPUT, 'assets.json')
                        fullPath   : no
                        prettyPrint: true
                        metadata:
                            git_ref   : GIT_REV
                            version   : SMC_VERSION
                            built     : BUILD_DATE
                            timestamp : BUILD_TS

# https://www.npmjs.com/package/html-webpack-plugin
HtmlWebpackPlugin = require('html-webpack-plugin')
# we need our own chunk sorter, because just by dependency doesn't work
# this way, we can be 100% sure
smcChunkSorter = (a, b) ->
    order = ['css', 'lib', 'smc']
    if order.indexOf(a.names[0]) < order.indexOf(b.names[0])
        return -1
    else
        return 1

# https://github.com/kangax/html-minifier#options-quick-reference
htmlMinifyOpts =
    empty: true
    removeComments: true
    minifyJS : true
    minifyCSS : true
    collapseWhitespace : true
    conservativeCollapse : true

# when base_url_html is set, it is hardcoded into the index page
# it mimics the logic of the hub, where all trailing slashes are removed
# i.e. the production page has a base url of '' and smc-in-smc has '/.../...'
base_url_html = BASE_URL # do *not* modify BASE_URL, it's needed with a '/' down below
while base_url_html and base_url_html[base_url_html.length-1] == '/'
    base_url_html = base_url_html.slice(0, base_url_html.length-1)

# this is the main index.html file, which should be served without any caching
jade2html = new HtmlWebpackPlugin
                        date             : BUILD_DATE
                        title            : TITLE
                        BASE_URL         : base_url_html
                        git_rev          : GIT_REV
                        mathjax          : MATHJAX_URL
                        filename         : 'index.html'
                        chunksSortMode   : smcChunkSorter
                        hash             : PRODMODE
                        template         : path.join(INPUT, 'index.jade')
                        minify           : htmlMinifyOpts
                        GOOGLE_ANALYTICS : GOOGLE_ANALYTICS

# the following set of plugins renders the policy pages
# they do *not* depend on any of the chunks, but rather specify css and favicon dependencies
# via lodash's template syntax. e.g.: <%= require('!file!bootstrap-3.3.0/css/bootstrap.min.css') %>
policyPages = []
for pp in (x for x in glob.sync('webapp-lib/policies/*.html') when path.basename(x)[0] != '_')
    policyPages.push new HtmlWebpackPlugin
                        filename : "policies/#{path.basename(pp)}"
                        inject   : 'head'
                        favicon  : path.join(INPUT, 'favicon.ico')
                        template : pp
                        chunks   : ['css']
                        minify   : htmlMinifyOpts

# video chat: not possible to render to html, while at the same time also supporting query parameters for files in the url
# maybe at some point https://github.com/webpack/webpack/issues/536 has an answer
videoChatSide = new HtmlWebpackPlugin
                        filename : "webrtc/group_chat_side.html"
                        inject   : 'head'
                        template : 'webapp-lib/webrtc/group_chat_side.html'
                        chunks   : []
                        minify   : htmlMinifyOpts
videoChatCell = new HtmlWebpackPlugin
                        filename : "webrtc/group_chat_cell.html"
                        inject   : 'head'
                        template : 'webapp-lib/webrtc/group_chat_cell.html'
                        chunks   : []
                        minify   : htmlMinifyOpts

# global css loader configuration
cssConfig = JSON.stringify(minimize: true, discardComments: {removeAll: true}, mergeLonghand: true, sourceMap: true)

###
# ExtractText for CSS should work, but doesn't. Also not necessary for our purposes ...
# Configuration left as a comment for future endeavours.

# https://webpack.github.io/docs/stylesheets.html
ExtractTextPlugin = require("extract-text-webpack-plugin")

# merge + minify of included CSS files
extractCSS = new ExtractTextPlugin("styles-[hash].css")
extractTextCss  = ExtractTextPlugin.extract("style", "css?sourceMap&#{cssConfig}")
extractTextSass = ExtractTextPlugin.extract("style", "css?#{cssConfig}!sass?sourceMap&indentedSyntax")
extractTextScss = ExtractTextPlugin.extract("style", "css?#{cssConfig}!sass?sourceMap")
extractTextLess = ExtractTextPlugin.extract("style", "css?#{cssConfig}!less?sourceMap")
###

# Custom plugin, to handle the quirky situation of extra *.html files.
# It was originally used to copy auxiliary .html files, but since there is
# no processing of the included style/js files (hashing them), it cannot be used.
# maybe it will be useful for something else in the future...
class LinkFilesIntoTargetPlugin
    constructor: (@files, @target) ->

    apply: (compiler) ->
        compiler.plugin "done", (comp) =>
            #console.log('compilation:', _.keys(comp.compilation))
            _.forEach @files, (fn) =>
                if fn[0] != '/'
                    src = path.join(path.resolve(__dirname, INPUT), fn)
                    dst = path.join(@target, fn)
                else
                    src = fn
                    fnrelative = fn[INPUT.length + 1 ..]
                    dst = path.join(@target, fnrelative)
                dst = path.resolve(__dirname, dst)
                console.log("hard-linking file:", src, "→", dst)
                dst_dir = path.dirname(dst)
                if not fs.existsSync(dst_dir)
                    fs.mkdir(dst_dir)
                fs.linkSync(src, dst) # mysteriously, that doesn't work

#policies = glob.sync(path.join(INPUT, 'policies', '*.html'))
#linkFilesIntoTargetPlugin = new LinkFilesToTargetPlugin(policies, OUTPUT)

###
CopyWebpackPlugin = require('copy-webpack-plugin')
copyWebpackPlugin = new CopyWebpackPlugin []
###

# this is like C's #ifdef for the source code. It is particularly useful in the
# source code of SMC, such that it knows about itself's version and where
# mathjax is. The version&date is shown in the hover-title in the footer (year).
setNODE_ENV         = new webpack.DefinePlugin
                                'process.env' :
                                   'NODE_ENV' : JSON.stringify(NODE_ENV)
                                'MATHJAX_URL' : JSON.stringify(MATHJAX_URL)
                                'SMC_VERSION' : JSON.stringify(SMC_VERSION)
                                'SMC_GIT_REV' : JSON.stringify(GIT_REV)
                                'BUILD_DATE'  : JSON.stringify(BUILD_DATE)
                                'BUILD_TS'    : JSON.stringify(BUILD_TS)

# This is not used, but maybe in the future.
# Writes a JSON file containing the main webpack-assets and their filenames.
{StatsWriterPlugin} = require("webpack-stats-plugin")
statsWriterPlugin   = new StatsWriterPlugin(filename: "webpack-stats.json")

# this is for debugging: adding it prints out a long long json of everything
# that ends up inside the chunks. that way, one knows exactly where which part did end up.
# (i.e. if require.ensure really creates chunkfiles, etc.)
class PrintChunksPlugin
    apply: (compiler) ->
        compiler.plugin 'compilation', (compilation, params) ->
            compilation.plugin 'after-optimize-chunk-assets', (chunks) ->
                console.log(chunks.map (c) ->
                        id: c.id
                        name: c.name
                        includes: c.modules.map (m) ->  m.request
                )


plugins = [
    cleanWebpackPlugin,
    #provideGlobals,
    setNODE_ENV,
    banner,
    jade2html,
    videoChatSide,
    videoChatCell,
    #commonsChunkPlugin,
    assetsPlugin,
    #extractCSS,
    #copyWebpackPlugin
    #webpackSHAHash,
    statsWriterPlugin,
    #new PrintChunksPlugin(),
    mathjaxVersionedSymlink,
    #linkFilesIntoTargetPlugin,
]

plugins = plugins.concat(policyPages)

if PRODMODE
    console.log "production mode: enabling compression"
    # https://webpack.github.io/docs/list-of-plugins.html#commonschunkplugin
    # plugins.push new webpack.optimize.CommonsChunkPlugin(name: "lib")
    plugins.push new webpack.optimize.DedupePlugin()
    plugins.push new webpack.optimize.OccurenceOrderPlugin()
    plugins.push new webpack.optimize.LimitChunkCountPlugin(maxChunks: 10)
    plugins.push new webpack.optimize.MinChunkSizePlugin(minChunkSize: 32768)
    # to get source maps working in production mode, one has to figure out how
    # to get inSourceMap/outSourceMap working here.
    plugins.push new webpack.optimize.UglifyJsPlugin
                                sourceMap: false
                                minimize: true
                                output:
                                    comments: new RegExp(TITLE,"g") # to keep the banner inserted above
                                mangle:
                                    except       : ['$super', '$', 'exports', 'require']
                                    screw_ie8    : true
                                compress:
                                    screw_ie8    : true
                                    warnings     : false
                                    properties   : true
                                    sequences    : true
                                    dead_code    : true
                                    conditionals : true
                                    comparisons  : true
                                    evaluate     : true
                                    booleans     : true
                                    unused       : true
                                    loops        : true
                                    hoist_funs   : true
                                    cascade      : true
                                    if_return    : true
                                    join_vars    : true
                                    drop_debugger: true
                                    negate_iife  : true
                                    unsafe       : true
                                    side_effects : true


# tuning generated filenames and the configs for the aux files loader.
if PRODMODE
    hashname = '[sha256:hash:base62:33].[ext]' # don't use base64, it's not recommended for some reason.
else
    hashname = '[path][name].[ext]'
pngconfig   = "name=#{hashname}&limit=16000&mimetype=image/png"
svgconfig   = "name=#{hashname}&limit=16000&mimetype=image/svg+xml"
icoconfig   = "name=#{hashname}&mimetype=image/x-icon"
woffconfig  = "name=#{hashname}&mimetype=application/font-woff"

module.exports =
    cache: true

    # https://webpack.github.io/docs/configuration.html#devtool
    # **do** use cheap-module-eval-source-map; it produces too large files, but who cares since we are not
    # using this in production.  DO NOT use 'source-map', which is VERY slow.
    devtool: if SOURCE_MAP then '#cheap-module-eval-source-map'

    entry: # ATTN don't alter or add names here, without changing the sorting function above!
        css  : 'webapp-css.coffee'
        lib  : 'webapp-lib.coffee'
        smc  : 'webapp-smc.coffee'

    output:
        path          : OUTPUT
        publicPath    : path.join(BASE_URL, OUTPUT) + '/'
        filename      : if PRODMODE then '[name]-[hash].js' else '[name].js'
        chunkFilename : if PRODMODE then '[id]-[hash].js'   else '[id].js'
        hashFunction  : 'sha256'

    module:
        loaders: [
            { test: /\.cjsx$/,   loaders: ['coffee-loader', 'cjsx-loader'] },
            { test: /\.coffee$/, loader: 'coffee-loader' },
            { test: /\.less$/,   loaders: ["style-loader", "css-loader", "less?#{cssConfig}"]}, #loader : extractTextLess }, #
            { test: /\.scss$/,   loaders: ["style-loader", "css-loader", "sass?#{cssConfig}"]}, #loader : extractTextScss }, #
            { test: /\.sass$/,   loaders: ["style-loader", "css-loader", "sass?#{cssConfig}&indentedSyntax"]}, # ,loader : extractTextSass }, #
            { test: /\.json$/,   loaders: ['json-loader'] },
            { test: /\.png$/,    loader: "url-loader?#{pngconfig}" },
            { test: /\.ico$/,    loader: "file-loader?#{icoconfig}" },
            { test: /\.svg(\?v=[0-9].[0-9].[0-9])?$/,    loader: "url-loader?#{svgconfig}" },
            { test: /\.(jpg|gif)$/,    loader: "file-loader"},
            # .html only for files in smc-webapp!
            { test: /\.html$/, include: [path.resolve(__dirname, 'smc-webapp')], loader: "raw!html-minify?conservativeCollapse"},
            # { test: /\.html$/, include: [path.resolve(__dirname, 'webapp-lib')], loader: "html-loader"},
            { test: /\.hbs$/,    loader: "handlebars-loader" },
            { test: /\.woff(2)?(\?v=[0-9].[0-9].[0-9])?$/, loader: "url-loader?#{woffconfig}" },
            { test: /\.(ttf|eot)(\?v=[0-9].[0-9].[0-9])?$/, loader: "file-loader?name=#{hashname}" },
            # { test: /\.css$/,    loader: 'style!css' },
            { test: /\.css$/, loaders: ["style-loader", "css-loader?#{cssConfig}"]}, # loader: extractTextCss }, #
            { test: /\.jade$/, loader: 'jade' },
        ]

    resolve:
        # So we can require('file') instead of require('file.coffee')
        extensions : ['', '.js', '.json', '.coffee', '.cjsx', '.scss', '.sass']
        root       : [path.resolve(__dirname),
                      path.resolve(__dirname, WEBAPP_LIB),
                      path.resolve(__dirname, 'smc-util'),
                      path.resolve(__dirname, 'smc-util/node_modules'),
                      path.resolve(__dirname, 'smc-webapp'),
                      path.resolve(__dirname, 'smc-webapp/node_modules')]

    plugins: plugins

    'html-minify-loader':
        empty                : true   # KEEP empty attributes
        cdata                : true   # KEEP CDATA from scripts
        comments             : false
        removeComments       : true
        minifyJS             : true
        minifyCSS            : true
        collapseWhitespace   : true
        conservativeCollapse : true   # absolutely necessary, also see above in module.loaders/.html
