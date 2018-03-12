##############################################################################
#
#    CoCalc: Collaborative Calculation in the Cloud
#
#    Copyright (C) 2015 -- 2018, SageMath, Inc.
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

# Examples Dialog
# This is a modal dialog, which downloads a hierarchical collection of code snippets
# with descriptions. It returns an object, containing the code and the language:
# {"code": "...", "lang" : "..."} via a given callback.
#
# The canonical project creating the appropriate datastructure is
# https://github.com/sagemathinc/cocalc-assistant

exports.REPO_URL = 'https://github.com/sagemathinc/cocalc-assistant'

# Usage:
# w = render_examples_dialog(target, project_id, filename, lang)
#     * target: jquery dom object, where react is put into
#     * project_id and filename to make state in redux unique
#     * lang is the mode (sage, r, python, ...)
# use 'w.set_handler' to set the handler that's used for inserting the selected document
# API (implemented in ExamplesActions)
# w.show([lang]) -- show dialog again (same state!) and in csae a language given, a selection of it is triggered

# global libs
_         = require('underscore')
immutable = require('immutable')
# react elements
{Col, Row, Panel, Button, FormGroup, Checkbox, FormControl, Well, Alert, Modal, Table, Nav, NavItem, ListGroup, ListGroupItem, InputGroup} = require('react-bootstrap')
{React, ReactDOM, redux, Redux, Actions, Store, rtypes, rclass} = require('../smc-react')
{Loading, Icon, Markdown, Space} = require('../r_misc')
# cocalc libs
{defaults, required, optional} = misc = require('smc-util/misc')
# assistant libs
{ExamplesDialog} = require('./dialog')

# used elsewhere, to make sure we use the same iconography everywhere
exports.ICON_NAME = 'magic'

# the json from the server, where the entries for the documents are
# double-nested objects (two hiearchies of categories) mapping to title/code/description documents
DATA = null

redux_name = (project_id, path) ->
    return "examples-#{project_id}-#{path}"

# convert a language like "python" or "r" (usually short and lowercase) to a canonical name
# TODO this should probably be part of the "data", or a more global function somewhere in the webapp.
exports.lang2name = (lang) ->
    if lang == 'python'
        return 'Python'
    else if lang == 'gap'
        return 'GAP'
    else if lang == 'sage' or misc.startswith(lang, 'sage-')
        return 'SageMath'
    else
        return lang.charAt(0).toUpperCase() + lang[1..]

# Redux stuff

INIT_STATE =
    cat0                : null # idx integer
    cat1                : null # idx integer
    cat2                : null # idx integer
    catlist0            : []
    catlist1            : []
    catlist2            : []
    code                : ''
    setup_code          : undefined
    descr               : ''
    hits                : []
    search_str          : null
    search_sel          : null
    submittable         : false
    cat1_top            : ["Introduction", "Tutorial", "Help"]
    unknown_lang        : false

makeExamplesStore = (NAME) ->
    name: NAME

    stateTypes:
        cat0                : rtypes.number      # index of selected first category (left)
        cat1                : rtypes.number      # index of selected second category (second from left)
        cat2                : rtypes.number      # index of selected third category (document titles)
        catlist0            : rtypes.arrayOf(rtypes.string)  # list of first category entries
        catlist1            : rtypes.arrayOf(rtypes.string)  # list of second level categories
        catlist2            : rtypes.arrayOf(rtypes.string)  # third level are the document titles
        code                : rtypes.string      # displayed content of selected document
        setup_code          : rtypes.string      # optional, common code in the sub-category
        prepend_setup_code  : rtypes.bool        # if true, setup code is prepended to code
        descr               : rtypes.string      # markdown-formatted content of document description
        hits                : rtypes.arrayOf(rtypes.array)  # search results
        search_str          : rtypes.string      # substring to search for -- or undefined
        search_sel          : rtypes.number      # index of selected matched documents
        submittable         : rtypes.bool        # if true, the buttons at the bottom are active
        cat1_top            : rtypes.arrayOf(rtypes.string)
        unknown_lang        : rtypes.bool        # true if there is no known set of documents for the language

    getInitialState: ->
        INIT_STATE

    data_lang: ->
        @get('data').get(@get('lang'))

    # First categories list, depends on selected language, sort order depends on cat1_top
    get_catlist0: () ->
        cat0 = @data_lang().keySeq().toArray()
        top = @get('cat1_top')
        cat0ordering = (el) ->
            i = - top.reverse().indexOf(el)
            return [i, el]
        return _.sortBy(cat0, cat0ordering)

    # Second level categories list, depends on selected index of first level
    # Sorted by cat1_top and a possible 'sortweight'
    get_catlist1: () ->
        k0 = @get_catlist0()[@get('cat0')]
        cat1data = @data_lang().get(k0)
        cat1 = cat1data.keySeq().toArray()
        top = @get('cat1_top')
        cat1ordering = (el) ->
            so = cat1data?.getIn([el, 'sortweight']) ? 0.0
            i = - top.reverse().indexOf(el)
            return [so, i, el]
        return _.sortBy(cat1, cat1ordering)

    # The titles of the selected documents are exactly as they're in the original data (they're an array)
    # That way, it's possible to create a coherent narrative from top to bottom
    get_catlist2: () ->
        k0 = @get_catlist0()[@get('cat0')]
        k1 = @get_catlist1()[@get('cat1')]
        return @data_lang().getIn([k0, k1, 'entries']).map((el) -> el.get(0)).toArray()


class ExamplesActions extends Actions
    _init: (store) ->
        @store = store

    get: (key) ->
        @store.get(key)

    set: (update) ->
        @setState(update)

    show: (lang) =>
        lang ?= 'sage'
        if lang != @get('lang')
            @init(lang)
        else
            @set(show: true)

    reset: ->
        @set(INIT_STATE)

    hide: =>
        @set(show: false)

    init: (lang) ->
        return if not lang?
        if not @get('initialized')
            @reset()
            @set(lang:lang)
            @load_data()
        else if @get('lang') != lang
            @select_lang(lang)
        @set
            show                : true
            initialized         : true
            prepend_setup_code  : @get('prepend_setup_code') ? true

    init_data: (data) ->
        @set(data: data)
        nav_entries = []
        for key, v of data
            if _.keys(v).length > 0
                nav_entries.push(key)
        @set(nav_entries: nav_entries)
        @select_lang(@get('lang'))

    set_handler: (handler) ->
        @set(handler:handler)

    insert: (descr) ->
        # this is the essential task of the example dialog:
        # call the callback with the selected code snippet
        code               = @get('code')
        setup_code         = @get('setup_code')
        prepend_setup_code = @get('prepend_setup_code')
        if (prepend_setup_code) and (setup_code?.length > 0)
            code = "#{setup_code}\n#{code}"
        ret =
            code  : code
            lang  : @get('lang')
            descr : if descr then @get('descr') else null
        @get('handler')?(ret)

    load_data: () ->
        if not DATA?
            require.ensure [], =>
                # DATA is a global variable!
                # this file is supposed to be in webapp-lib/examples/examples.json
                # follow "./install.py examples" to see how the makefile is called during build
                DATA = require('webapp-lib/examples/examples.json')
                @init_data(DATA)
        else
            @init_data(DATA)

    # when a language is selected, this resets the category selections
    select_lang: (lang) ->
        return if lang? == @get('lang')
        lang ?= @get('lang')
        @reset()
        data = @get('data')
        if data.has(lang)
            @set(lang: lang)
            catlist0 = @store.get_catlist0()
            @set(catlist0 : catlist0)
            if catlist0.length == 1
                @set_selected_category(0, 0)
        else
            @set(unknown_lang:true)

    # a search is performed. basically looks through the documents until it finds enough results ...
    search: (search_str) ->
        @reset()
        if not search_str? or search_str.length == 0
            @select_lang(@get('lang'))
            return
        @set(search_str : search_str)
        str = search_str.toLowerCase()
        hits = []
        data_lang = @store.data_lang()
        EnoughResultsException = {}
        try
            data_lang.forEach (data1, lvl1) ->
                data1.forEach (data2, lvl2) ->
                    data2.get('entries').forEach (doc, lvl3) ->
                        title = doc.get(0)
                        descr = doc.getIn([1, 1])
                        inTitle = title.toLowerCase().indexOf(str)
                        inDescr = descr.toLowerCase().indexOf(str)
                        if inTitle != -1 or inDescr != -1
                            hits.push([lvl1, lvl2, lvl3, title, descr, inDescr])
                            if hits.length >= 30
                                throw EnoughResultsException
        catch ex
            if ex isnt EnoughResultsException
                throw ex
        @set(hits: hits)

    # a specific search result is selected and the corresponding document is set to be shown to the user
    search_selected: (idx) ->
        # why is @get('hits') immutable ?
        [lvl1, lvl2, lvl3, title, descr, inDescr] = @get('hits').get(idx).toArray()
        doc = @store.data_lang().getIn([lvl1, lvl2, 'entries', lvl3])
        @show_doc(doc)
        @set(search_sel : idx)

    # keyboard handling for the search list
    search_cursor: (dir) ->
        # searching and then cursor-selecting search results
        # dir: +1 → downward / -1 → upward
        return if not @get('hits')?
        l = @get('hits').size
        if not @get('search_sel')?
            if dir > 0
                new_sel = 0
            else
                new_sel = l - 1
        else
            l = @get('hits').size
            new_sel = (@get('search_sel') + dir) %% l
            if new_sel < 0
                new_sel = l - 1
        @set(search_sel : new_sel)
        @search_selected(new_sel)

    # for a specific document, set the code and description box values.
    show_doc: (doc) ->
        @set
            code        : doc.getIn([1, 0])
            descr       : doc.getIn([1, 1])
            submittable : true

    # key handling for the categories selection.
    # there is also a "twist": it wraps around at the end of a category to the next higher category
    # (similar to a counter with carry) but the lenght of the categories changes!
    select_cursor: (dir) ->
        # dir: only 1 or -1!
        # +1 → downward, higher idx number, first in list
        # -1 → upwards, lower index, last in list
        cat0 = @get('cat0')
        cat1 = @get('cat1')
        cat2 = @get('cat2')
        # console.log 'cat0', cat0, 'cat1', cat1, 'cat2', cat2
        top_or_bottom = (list) ->
            if dir < 0 then list.length - 1 else 0
        # dealing with some corner cases first
        if not cat0?
            catlist0 = @store.get_catlist0()
            if catlist0?.length > 0
                @set_selected_category(0, top_or_bottom(catlist0))
        else if not cat1?
            catlist1 = @store.get_catlist1()
            if catlist1?.length > 0
                @set_selected_category(1, top_or_bottom(catlist1))
        else if not cat2?
            catlist2 = @store.get_catlist2()
            if catlist2?.length > 0
                @set_selected_category(2, top_or_bottom(catlist2))
        else # cat0 1 and 2 are defined (i.e. we have a selection)
            l0 = @get('catlist0').size
            l1 = @get('catlist1').size
            l2 = @get('catlist2').size
            cat2_next = cat2 + dir

            # the next two blocks take care of carry in cat 2 and 1
            # trick: to accomodate for lists of varying length, an index
            # of -1 is fine -- see @set_selected_category
            if cat2_next < 0
                cat1_next = cat1 - 1
            else if cat2_next >= l2
                cat2_next = 0
                cat1_next = cat1 + 1

            if cat1_next < 0
                cat0_next = cat0 - 1
            else if cat1_next >= l1
                cat1_next = 0
                cat0_next = cat0 + 1

            if cat0_next?
                # wrap cat0 around (no curry)
                cat0_next = (cat0_next) % l0
                if cat0_next < 0
                    cat0_next = l0 - 1
                @set_selected_category(0, cat0_next)
            if cat1_next?
                @set_selected_category(1, cat1_next)
            @set_selected_category(2, cat2_next)

    # this sets a selected category for a given level.
    # it is able to handle negative indices (wraps around nicely) and it also expands
    # subcategories, if there is only one choice.
    set_selected_category: (level, idx) ->
        lang = @store.data_lang()
        switch level
            when 0, 1
                @set
                    code        : ''
                    descr       : ''
                    cat2        : null
                    submittable : false
                    setup_code  : ''

        switch level
            when 0
                @set(cat0: if idx == -1 then @get('catlist0').size - 1 else idx)
                catlist1 = @store.get_catlist1()
                @set
                    cat1       : null
                    cat2       : null
                    catlist1   : catlist1
                    catlist2   : []
                if catlist1.length == 1
                    @set_selected_category(1, 0)

            when 1
                cat0     = @get('cat0')
                @set(cat1 : if idx == -1 then @get('catlist1').size - 1 else idx)
                catlist2 = @store.get_catlist2()
                @set
                    cat2       : undefined
                    catlist2   : catlist2
                if catlist2.length == 1
                    @set_selected_category(2, 0)

            when 2
                k0    = @get('catlist0').get(@get('cat0'))
                k1    = @get('catlist1').get(@get('cat1'))
                idx   = if idx == -1 then @get('catlist2').size - 1 else idx
                doc   = lang.getIn([k0, k1, 'entries', idx])
                setup = lang.getIn([k0, k1, 'setup'])
                @set(cat2:idx, setup_code:setup)
                @show_doc(doc)


### Public API ###

init_action_and_store = (name) ->
    store   = redux.createStore(makeExamplesStore(name))
    actions = redux.createActions(name, ExamplesActions)
    actions._init(store)
    return [actions, store]

# The following two exports are used in jupyter/main and ./register
exports.instantiate_assistant = (project_id, path) ->
    name = redux_name(project_id, path)
    actions = redux.getActions(name)
    if not actions?
        [actions, store] = init_action_and_store(name)
    return actions

exports.instantiate_component = (project_id, path, actions) ->
    name = redux_name(project_id, path)
    W = ExamplesDialog(name)
    return <Redux redux={redux}><W actions={actions}/></Redux>

# and this one below is used in editor.coffee for sagews worksheets.
# "target" is a DOM element somewhere in the buttonbar of the editor's html
exports.render_examples_dialog = (opts) ->
    opts = defaults opts,
        target     : required
        project_id : required
        path       : required
        lang       : 'sage'
    name = redux_name(opts.project_id, opts.path)
    actions = redux.getActions(name)
    if not actions?
        [actions, store] = init_action_and_store(name)
    actions.init(opts.lang)
    actions.set(lang_select:true)
    W = ExamplesDialog(name)
    ReactDOM.render(<Redux redux={redux}><W actions={actions}/></Redux>, opts.target)
    return actions