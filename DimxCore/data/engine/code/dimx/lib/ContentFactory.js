import * as dimxCpp from 'dimx-cpp'
import {Templates} from './ContentTemplates'

export class ContentFactory {
    templates = {}
    // Records by the Anchor name their `A` keys; and by prefix for an `A` ending
    // in '*' ("REWARD_*" - the one wildcard; '' and '*' are every Anchor).
    content = {}
    prefixContent = []
    apps = {}

    constructor() {
        for (const tmpl of Templates) {
            this.registerTemplate(tmpl.name, tmpl.config, tmpl.handler)
        }
    }

    getApp(name) {
        if (!(name in this.apps)) {
            this.apps[name] = dimxCpp.getApp(name);
            if (!this.apps[name]) {
                throw new Error(`ContentFactory: Unknown app [${name}]`)
            }
        }
        return this.apps[name]
    }

    expandTemplate(record, visited) {
        if (!record.T) {
            return record
        }

        if (record.T in visited) {
            console.error(`Circular dependency detected: template [${JSON.stringify(record)}] visited [${JSON.stringify(visited)}]`)
            return null
        }
        visited[record.T] = true

        let baseTmpl = this.templates[record.T]
        if (!baseTmpl) {
            console.error(`Unknown base template [${record.T}]`)
            return null
        }

        for (const key of Object.keys(record)) {
            if (key[0] === '_' || key === 'T') {
                continue
            }

            const baseField = baseTmpl[key]
            if (baseField === undefined) {
                console.error(`Unknown field [${key}] in template derived from [${record.T}]`)
                return null
            }
        }

        return {...baseTmpl, ...record}
    }

    registerTemplate(name, template, handler) {
        if (!name || !template /*|| !handler*/) {
            console.error(`Null template [${name}]. Ignoring`)
            return;
        }
        if (name in this.templates) {
            console.error(`Template [${name}] already defined. Ignoring the duplicate`)
            return;
        }
        let expandedRec = this.expandTemplate(template, {})
        if (!expandedRec) {
            console.error(`Failed to expand content template [${name}] [${JSON.stringify(template)}]`)
            return;
        }

        if (handler) {
            expandedRec._handler_ = handler
        }

        this.templates[name] = expandedRec;
    }

    addContent(content, options = {}) {
        if (!content || !Array.isArray(content)) {
            console.error(`Invalid content being added [${JSON.stringify(content)}]`)
            return
        }
        // The root ("apps/x", "dxp/x") the records' entities are made under: the
        // one named, else the calling script's. The app they belong to: the one
        // named, else the app at that root, else the app of the calling script -
        // records an app's code adds itself (dxp/james-webb names only its
        // appPath) are that app's like its content module's, made for the
        // Anchors standing when it comes up and held to its declaration.
        const root = options.app ?? options.appPath ?? dimxCpp.appRoot()
        const appName = options.appName || dimxCpp.appNameOf(root ?? '') || dimxCpp.callerApp()
        // An app's records are held against its anchors.json first: a key
        // outside the declaration throws here, and nothing of the batch is kept.
        if (appName) {
            const keys = content.map(record => record.A).filter(key => typeof key === 'string')
            dimxCpp.checkAnchors(appName, [...new Set(keys)])
        }
        for (const record of content) {
            const recordKey = record.A
            delete record.A
            if (typeof recordKey !== 'string') {
                console.error(`Content record without an Anchor name (A): ${JSON.stringify(record)}`)
                continue
            }
            // The app whose code is loaded before the records are made
            // (createContent); none for records of no app's script.
            record._app_name_ = appName || undefined
            record._app_path_ = options.appPath
            record._app_root_ = root || undefined
            this.recordsAt(recordKey).push(record)
        }
    }

    // Which apps' records have been made for an Anchor: a Set of app names ('' for
    // records of no app) per Anchor object. Three paths make them - createContent
    // when the Anchor appears, its deferred half once an app it waited for is up,
    // and createForApp for the Anchors an app found standing - and an Anchor that
    // appears while its app comes up meets two of them. One JS object per entity,
    // so an Anchor made again (a location entered again) is a new key, and the map
    // forgets the old one with it.
    made = new WeakMap()

    // True, once, for the first path to make `app`'s records for `object`.
    claim(object, app) {
        let apps = this.made.get(object)
        if (!apps) {
            apps = new Set()
            this.made.set(object, apps)
        }
        if (apps.has(app)) {
            return false
        }
        apps.add(app)
        return true
    }

    // The records of one app ('' - of none) for an Anchor's name.
    appRecordsFor(name, app) {
        return this.recordsFor(name).filter(record => (record._app_name_ ?? '') === app)
    }

    // The list a key's records go in: the name's, or the prefix's for a key ending in '*'.
    recordsAt(key) {
        if (key !== '' && key !== '*' && !key.endsWith('*')) {
            return this.content[key] ?? (this.content[key] = [])
        }
        const prefix = key.endsWith('*') ? key.slice(0, -1) : key
        let entry = this.prefixContent.find(entry => entry.prefix === prefix)
        if (!entry) {
            entry = { prefix, records: [] }
            this.prefixContent.push(entry)
        }
        return entry.records
    }

    // The records for an Anchor: those keyed by its name, and those keyed by a prefix of it.
    recordsFor(name) {
        const records = [...(this.content[name] ?? [])]
        for (const entry of this.prefixContent) {
            if (name.startsWith(entry.prefix)) {
                records.push(...entry.records)
            }
        }
        return records
    }

    expandRecord(record, tmpl) {
        if (!tmpl) {
            console.error(`Unknown item template [${record.T}]`)
            return null
        }

        for (const key of Object.keys(record)) {
            if (key[0] != '_' && key != 'T' && !(key in tmpl)) {
                console.error(`Invalid key [${key}] in content item [${JSON.stringify(record)}]`)
                return null
            }
        }
        const expanded = {...tmpl, ...record}

        if (expanded._meta_) {
            // A resource a record names is checked through the record's app, where
            // a local name resolves to the app's own file first - and left as it
            // is: the entity carries the app (makeEntityConfig) and the engine
            // resolves the name there. It used to be rewritten to the absolute path.
            const root = expanded._app_root_
            for (const [key, info] of Object.entries(expanded._meta_)) {
                if (!info.resource) {
                    continue
                }
                const value = expanded[key];
                if (!value) {
                    continue
                }
                const found = root
                    ? dimxCpp.utils.validateResourceIn(info.resource, value, root)
                    : dimxCpp.utils.validateResource(info.resource, value)
                if (!found) {
                    console.error(`Unable to locate content resource [${info.resource}] [${value}]`)
                    return null
                }
            }
        }

        delete expanded._meta_;
        delete expanded._app_name_;
        delete expanded._app_path_;
        // _app_root_ stays: the handler's entity config takes it (makeEntityConfig).
        return expanded
    }

    // The records keyed by this Anchor, by app. An app whose code is not up yet
    // is loaded first - its code may register the templates its records use -
    // and its records are made when it is; the others, and records of no app's
    // listing (added by a script that is running), are made now.
    createContent(object) {
        const array = this.recordsFor(object.name)
        if (!array.length) {
            return
        }
        const byApp = new Map()
        for (const record of array) {
            const app = record._app_name_ ?? ''
            if (!byApp.has(app)) {
                byApp.set(app, [])
            }
            byApp.get(app).push(record)
        }
        for (const [app, records] of byApp) {
            if (app && !dimxCpp.appLoaded(app)) {
                // Its records as they stand once it is up: its code may add more.
                dimxCpp.loadApp(app).then(
                    () => {
                        if (this.claim(object, app)) {
                            this.createRecords(object, this.appRecordsFor(object.name, app))
                        }
                    },
                    (e) => console.error(`Content for [${object.name}] not created: ${e}`))
            } else if (this.claim(object, app)) {
                this.createRecords(object, records)
            }
        }
    }

    // The records of `appName` for the Anchors standing already: its content
    // came with its code, after them, and nothing else makes these. Called by
    // the engine once the app is up, so the templates its code registers are
    // there (JsDimensionController::finishApp).
    createForApp(appName) {
        for (const anchor of dimxCpp.standingAnchors()) {
            const records = this.appRecordsFor(anchor.name, appName)
            if (records.length && this.claim(anchor, appName)) {
                this.createRecords(anchor, records)
            }
        }
    }

    createRecords(object, array) {
        for (let record of array) {
            const tmpl = this.templates[record.T]
            if (!tmpl) {
                console.warn(`Unknown template [${record.T}] for object [${object.name}]`)
                continue
            }

            if (!tmpl._handler_) {
                console.warn(`Unknown content handler [${tmpl.T}] for object [${object.name}]`)
                continue
            }

            let expandedRecord = this.expandRecord(record, tmpl)
            if (!expandedRecord) {
                continue
            }

            tmpl._handler_(object, expandedRecord)
        }
    }

}
