#!/bin/sh
# Read-only diagnostics for testing OpenNotch on a Mac. Needs no privacy permission and changes no
# setting. Its only writes are a read-only copy of the wallpaper store's Index.plist and a copy of
# this report, both in ~/Desktop/OpenNotch-backup.
set -eu

index="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
support="$HOME/Library/Application Support/OpenNotch"
backup_dir="$HOME/Desktop/OpenNotch-backup"
stamp=$(date +%Y%m%d-%H%M%S)
mkdir -p "$backup_dir"

{
    echo "OpenNotch Mac probe, $(date)"

    echo
    echo "== Wallpaper store backup"
    if [ -f "$index" ]; then
        cp "$index" "$backup_dir/Index-$stamp.plist"
        chmod 444 "$backup_dir/Index-$stamp.plist"
        echo "Copied $index to $backup_dir/Index-$stamp.plist (read-only)"
    else
        echo "No file at $index"
    fi

    echo
    echo "== macOS"
    sw_vers

    echo
    echo "== Model"
    system_profiler SPHardwareDataType | sed -n -E '/Model Name|Model Identifier|Chip|Memory/p'

    echo
    echo "== Displays (system_profiler)"
    system_profiler SPDisplaysDataType | sed -n '/^ *Displays:$/,$p' | sed '/[Ss]erial/d'

    echo
    echo "== Apps"
    for name in OpenNotch TopNotch; do
        if pgrep -x "$name" >/dev/null; then echo "$name: running"; else echo "$name: not running"; fi
    done
    if [ -d /Applications/OpenNotch.app ]; then echo "/Applications/OpenNotch.app: installed"; else echo "/Applications/OpenNotch.app: not installed"; fi

    echo
    echo "== OpenNotch settings and saved originals"
    defaults read io.github.rabbive.OpenNotch 2>&1 || true
    if [ -f "$support/applied.json" ]; then cat "$support/applied.json"; echo; else echo "No $support/applied.json"; fi
    ls -l "$support/Renders" 2>&1 || true

    INDEX_PLIST="$index" osascript -l JavaScript <<'JXA'
const NSISOLatin1StringEncoding = 5
const imageProvider = 'com.apple.wallpaper.choice.image'
const rendersFolder = '/Library/Application Support/OpenNotch/Renders/'
const pictureFolders = ['/System/Library/Desktop Pictures', '/Library/Desktop Pictures']

function run() {
  ObjC.import('AppKit')
  const context = { out: [], labels: {} }
  const out = context.out
  let screens = []
  let spaceLists = []
  let store

  section(out, 'Screens (NSScreen, as OpenNotch reads them)', () => {
    screens = readScreens()
    for (const screen of screens) {
      if (typeof screen.uuid === 'string') context.labels[screen.uuid] = screen.name
      describeScreen(screen, out)
    }
  })

  section(out, 'Spaces (SkyLight, as OpenNotch reads them)', () => {
    spaceLists = readSpaces()
    for (const list of spaceLists) {
      for (const space of list.spaces) context.labels[space.uuid] = spaceLabel(space, list)
    }
    describeSpaces(spaceLists, context)
  })

  section(out, 'Wallpaper store', () => {
    const path = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('INDEX_PLIST'))
    const data = $.NSData.dataWithContentsOfFile(path)
    if (data.isNil()) throw new Error(`can't read ${path}`)
    store = plain($.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data, 0, null, null))
    out.push(`${path}, ${Number(data.length)} bytes, top-level keys: ${keysOf(store).map(showKey).join(', ')}`)
  })

  section(out, 'Wallpaper choices in the store (every Desktop and Idle entry)', () => {
    if (!store) throw new Error('no wallpaper store')
    describeChoices(store, context)
  })

  section(out, 'What OpenNotch would paint on each screen', () => {
    if (screens.length === 0) throw new Error('no screens read')
    for (const screen of screens) describeResolution(screen, spacesFor(spaceLists, screen.uuid), store, context)
  })

  section(out, 'Multi-frame (dynamic) HEIC files', () => {
    for (const folder of pictureFolders) describeDynamicFiles(folder, out)
  })

  section(out, 'Wallpaper store, full structure (nested plist data decoded)', () => {
    if (!store) throw new Error('no wallpaper store')
    dump(store, 0, undefined, context)
  })

  return out.join('\n')
}

function section(out, title, body) {
  out.push('', `== ${title}`)
  try {
    body()
  } catch (error) {
    out.push(`unavailable: ${error}`)
  }
}

function attempt(body) {
  try {
    return body()
  } catch (error) {
    return { unavailable: String(error) }
  }
}

function show(value) {
  if (value === undefined || value === null) return 'none'
  if (typeof value === 'object' && 'unavailable' in value) return `unavailable (${value.unavailable})`
  return String(value)
}

function bind(name, signature) {
  if (typeof $[name] !== 'function') ObjC.bindFunction(name, signature)
  return $[name]
}

// The bridge: Foundation objects in, plain JS trees out. Everything below the bridge works on trees.

function plain(object) {
  if (object === undefined || object === null || object.isNil()) return { type: 'nil' }
  if (object.isKindOfClass($.NSDictionary)) {
    const keys = object.allKeys
    const entries = []
    for (let i = 0; i < keys.count; i++) {
      const key = keys.objectAtIndex(i)
      entries.push([String(ObjC.unwrap(key)), plain(object.objectForKey(key))])
    }
    entries.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    return { type: 'dict', entries }
  }
  if (object.isKindOfClass($.NSArray)) {
    const items = []
    for (let i = 0; i < object.count; i++) items.push(plain(object.objectAtIndex(i)))
    return { type: 'array', items }
  }
  if (object.isKindOfClass($.NSData)) return plainData(object)
  if (object.isKindOfClass($.NSString)) return { type: 'string', value: ObjC.unwrap(object) }
  if (object.isKindOfClass($.NSNumber)) {
    const value = ObjC.unwrap(object)
    return { type: typeof value === 'boolean' ? 'bool' : 'number', value }
  }
  if (object.isKindOfClass($.NSDate)) return { type: 'date', value: ObjC.unwrap(object.description) }
  return { type: 'object', value: ObjC.unwrap(object.description) }
}

// Configuration blobs are plists inside the plist, the way WallpaperSource.swift reads them.
function plainData(data) {
  const length = Number(data.length)
  const prefix = data.subdataWithRange({ location: 0, length: Math.min(length, 8) })
  const head = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(prefix, NSISOLatin1StringEncoding)) || ''
  const node = { type: 'data', length, head: head.replace(/[^\x20-\x7e]/g, '.') }
  if (head.startsWith('bplist') || head.startsWith('<?xml') || head.startsWith('<plist')) {
    node.plist = plain($.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data, 0, null, null))
  } else if (head.startsWith('book')) {
    const bookmark = attempt(() => ObjC.unwrap($.NSURL.resourceValuesForKeysFromBookmarkData([$.NSURLPathKey], data).objectForKey($.NSURLPathKey)))
    if (typeof bookmark === 'string') node.bookmarkPath = bookmark
  }
  return node
}

function readScreens() {
  const workspace = $.NSWorkspace.sharedWorkspace
  const list = $.NSScreen.screens
  const screens = []
  for (let i = 0; i < list.count; i++) {
    const screen = list.objectAtIndex(i)
    const id = ObjC.unwrap(screen.deviceDescription.objectForKey('NSScreenNumber'))
    const frame = screen.frame
    const visible = screen.visibleFrame
    const url = attempt(() => workspace.desktopImageURLForScreen(screen))
    screens.push({
      name: ObjC.unwrap(screen.localizedName),
      id,
      uuid: attempt(() => {
        const createUUID = bind('CGDisplayCreateUUIDFromDisplayID', ['id', ['unsigned int']])
        const uuidString = bind('CFUUIDCreateString', ['id', ['id', 'id']])
        return ObjC.unwrap(uuidString(null, createUUID(id)))
      }),
      builtin: attempt(() => bind('CGDisplayIsBuiltin', ['unsigned int', ['unsigned int']])(id) !== 0),
      width: frame.size.width,
      height: frame.size.height,
      scale: screen.backingScaleFactor,
      menuBar: frame.origin.y + frame.size.height - (visible.origin.y + visible.size.height),
      safeAreaTop: attempt(() => screen.safeAreaInsets.top),
      wallpaper: attempt(() => (url.isNil() ? undefined : ObjC.unwrap(url.isFileURL ? url.path : url.absoluteString))),
      wallpaperIsFile: attempt(() => !url.isNil() && url.isFileURL),
      options: attempt(() => plain(workspace.desktopImageOptionsForScreen(screen))),
    })
  }
  return screens.filter((s) => s.builtin === true).concat(screens.filter((s) => s.builtin !== true))
}

// Mirrors SpaceTracker.parse.
function readSpaces() {
  const main = bind('SLSMainConnectionID', ['int', []])
  const copy = bind('SLSCopyManagedDisplaySpaces', ['id', ['int']])
  return parseSpaces(plain(copy(main())))
}

function frameCount(path) {
  if (!$.NSFileManager.defaultManager.fileExistsAtPath(path)) return 0
  const create = bind('CGImageSourceCreateWithURL', ['id', ['id', 'id']])
  const count = bind('CGImageSourceGetCount', ['unsigned long', ['id']])
  const source = create($.NSURL.fileURLWithPath(path), null)
  return source.isNil() ? 0 : Number(count(source))
}

// Center placement draws the image at its pixel size; macOS may use its point size (from its DPI).
function imageSize(path) {
  const image = $.NSImage.alloc.initWithContentsOfFile(path)
  const rep = image.representations.objectAtIndex(0)
  return `${rep.pixelsWide} x ${rep.pixelsHigh} px, ${image.size.width} x ${image.size.height} pt`
}

// Mirrors WallpaperSource.classify.
function classify(path) {
  const frames = attempt(() => frameCount(path))
  const size = show(attempt(() => imageSize(path)))
  if (typeof frames !== 'number') return { kind: 'unknown', text: `can't read frames: ${show(frames)}` }
  if (frames === 0) return { kind: 'none', text: 'not an image file' }
  if (frames === 1) return { kind: 'image', text: `still image (1 frame, ${size})` }
  return { kind: 'dynamic', text: `multi-frame image (${frames} frames, ${size}); dynamic if it carries apple_desktop tags` }
}

function describeDynamicFiles(folder, out) {
  const subpaths = $.NSFileManager.defaultManager.subpathsAtPath(folder)
  if (subpaths.isNil()) {
    out.push(`${folder}: not found`)
    return
  }
  const heics = []
  for (let i = 0; i < subpaths.count; i++) {
    const subpath = ObjC.unwrap(subpaths.objectAtIndex(i))
    if (/\.heic$/i.test(subpath)) heics.push(`${folder}/${subpath}`)
  }
  const dynamic = heics.map((path) => [path, attempt(() => frameCount(path))]).filter(([, frames]) => typeof frames !== 'number' || frames > 1)
  out.push(`${folder}: ${heics.length} HEIC files, ${dynamic.length} with more than one frame`)
  for (const [path, frames] of dynamic) out.push(`  ${path}: ${typeof frames === 'number' ? `${frames} frames` : show(frames)}`)
}

// Everything from here on is pure: plain trees in, report lines out.

function get(node, key) {
  if (!node || node.type !== 'dict') return undefined
  const entry = node.entries.find(([name]) => name === key)
  return entry ? entry[1] : undefined
}

function items(node) {
  return node && node.type === 'array' ? node.items : []
}

function scalar(node) {
  return node && node.type !== 'dict' && node.type !== 'array' && node.type !== 'data' ? node.value : undefined
}

function keysOf(node) {
  return node && node.type === 'dict' ? node.entries.map(([key]) => key) : []
}

function showKey(key, labels) {
  const name = key === '' ? '""' : key
  return labels && labels[key] ? `${name} (${labels[key]})` : name
}

// Mirrors BarGeometry.init(frame:visibleFrame:safeAreaTop:scale:).
function band(screen) {
  const safeAreaTop = typeof screen.safeAreaTop === 'number' ? screen.safeAreaTop : 0
  const points = Math.max(screen.menuBar, safeAreaTop, 0)
  return {
    points,
    pixels: Math.ceil(points * screen.scale),
    canvas: `${Math.round(screen.width * screen.scale)} x ${Math.round(screen.height * screen.scale)}`,
  }
}

// Mirrors DesktopOptions.placement. NSImageScaling: 1 is axesIndependently, 2 is none.
function placement(options) {
  const scaling = scalar(get(options, 'NSWorkspaceDesktopImageScalingKey'))
  const clipping = scalar(get(options, 'NSWorkspaceDesktopImageAllowClippingKey'))
  if (scaling === 1) return 'stretch'
  if (scaling === 2) return 'center'
  return clipping === undefined || clipping ? 'fill' : 'fit'
}

function describeScreen(screen, out) {
  const builtin = screen.builtin === true ? 'built-in' : screen.builtin === false ? 'external' : `built-in ${show(screen.builtin)}`
  const geometry = band(screen)
  out.push(`${screen.name} (${builtin}), display ID ${screen.id}, UUID ${show(screen.uuid)}`)
  out.push(`  size ${screen.width} x ${screen.height} pt at scale ${screen.scale}, so OpenNotch renders ${geometry.canvas} px`)
  out.push(`  menu bar ${screen.menuBar} pt (frame top minus visibleFrame top), safe area top ${show(screen.safeAreaTop)} pt`)
  out.push(`  OpenNotch band: ${geometry.points} pt, ${geometry.pixels} px`)
  out.push(`  desktopImageURL: ${show(screen.wallpaper)}`)
  if (screen.options && screen.options.type === 'dict') {
    for (const [key, value] of screen.options.entries) out.push(`  option ${key}: ${value.type} ${show(value.value)}`)
    out.push(`  placement as OpenNotch reads it: ${placement(screen.options)}`)
  } else {
    out.push(`  desktopImageOptions: ${show(screen.options)}`)
  }
}

// Mirrors SpaceTracker.parse: desktop Spaces are type 0 and numbered in order.
function parseSpaces(list) {
  return items(list).map((entry) => {
    let desktops = 0
    const spaces = items(get(entry, 'Spaces'))
      .filter((space) => typeof scalar(get(space, 'uuid')) === 'string')
      .map((space) => {
        const isDesktop = scalar(get(space, 'type')) === 0
        if (isDesktop) desktops += 1
        return { uuid: scalar(get(space, 'uuid')), type: scalar(get(space, 'type')), number: isDesktop ? desktops : undefined }
      })
    return {
      display: scalar(get(entry, 'Display Identifier')),
      current: scalar(get(get(entry, 'Current Space'), 'uuid')),
      spaces,
    }
  })
}

// Mirrors SpaceTracker.spaces(display:): the matching display, or the only list there is.
function spacesFor(lists, display) {
  const list = lists.find((candidate) => candidate.display === display) || (lists.length === 1 ? lists[0] : undefined)
  return list && list.spaces.some((space) => space.uuid === list.current) ? list : undefined
}

function spaceLabel(space, list) {
  return `${space.number ? `Desktop ${space.number}` : 'full-screen Space'}${space.uuid === list.current ? ', current' : ''}`
}

function describeSpaces(lists, context) {
  for (const list of lists) {
    context.out.push(`Display Identifier ${showKey(String(list.display), context.labels)}`)
    for (const space of list.spaces) context.out.push(`  ${showKey(space.uuid)}: type ${space.type}, ${spaceLabel(space, list)}`)
  }
}

function choiceSets(node, path, found) {
  if (node.type === 'dict') {
    for (const [key, value] of node.entries) {
      const choices = get(get(value, 'Content'), 'Choices')
      if (choices && choices.type === 'array') found.push({ path, kind: key, entry: value, parent: node })
      else choiceSets(value, path.concat(key), found)
    }
  } else if (node.type === 'array') {
    node.items.forEach((item, i) => choiceSets(item, path.concat(`[${i}]`), found))
  }
  return found
}

function describeData(node) {
  if (node.plist) return `data, ${node.length} bytes, a nested plist:`
  if (node.bookmarkPath) return `data, ${node.length} bytes, a bookmark to ${JSON.stringify(node.bookmarkPath)}`
  return `data, ${node.length} bytes, starts ${JSON.stringify(node.head)}`
}

function flatten(node, prefix, lines) {
  if (node.type === 'dict' || node.type === 'array') {
    const children = node.type === 'dict' ? node.entries : node.items.map((item, i) => [`[${i}]`, item])
    if (children.length === 0) lines.push(`${prefix} = (empty ${node.type})`)
    for (const [key, child] of children) flatten(child, prefix ? `${prefix}.${showKey(key)}` : showKey(key), lines)
  } else if (node.type === 'data') {
    if (node.plist) flatten(node.plist, prefix, lines)
    else lines.push(`${prefix} = ${describeData(node)}`)
  } else {
    lines.push(`${prefix} = ${node.type === 'string' ? JSON.stringify(node.value) : show(node.value)}`)
  }
  return lines
}

function describeChoices(store, context) {
  const sets = choiceSets(store, [], [])
  if (sets.length === 0) context.out.push('No entry with Content.Choices found')
  for (const set of sets) {
    const where = set.path.map((key) => showKey(key, context.labels)).join(' / ') || '(top level)'
    const content = get(set.entry, 'Content')
    context.out.push(`${where} / ${set.kind}`)
    for (const [key, value] of set.parent.entries) {
      if (scalar(value) !== undefined) context.out.push(`  beside it, ${key}: ${JSON.stringify(scalar(value))}`)
    }
    for (const [key, value] of set.entry.entries) {
      if (key !== 'Content') context.out.push(`  ${key}: ${value.type === 'data' ? describeData(value) : show(scalar(value) !== undefined ? scalar(value) : value.type)}`)
    }
    items(get(content, 'Choices')).forEach((choice, i) => {
      context.out.push(`  choice ${i + 1}: Provider ${show(scalar(get(choice, 'Provider')))}`)
      for (const [key, value] of choice.entries || []) {
        if (key !== 'Provider') for (const line of flatten(value, key, [])) context.out.push(`    ${line}`)
      }
    })
    for (const [key, value] of content.entries) {
      if (key === 'Choices') continue
      const text = value.type === 'data' ? describeData(value).replace(/:$/, '') : value.type === 'dict' || value.type === 'array' ? value.type : JSON.stringify(scalar(value))
      context.out.push(`  Content.${key}: ${text}`)
    }
  }
}

// Mirrors IndexPlist.imageURL: the first candidate with a Desktop dict decides, with no fallthrough.
function storeLookup(store, display, space) {
  const spaceEntry = space === undefined ? undefined : get(get(store, 'Spaces'), space)
  const candidates = [
    [`Spaces / ${showKey(String(space))} / Displays / ${display}`, get(get(spaceEntry, 'Displays'), display)],
    [`Spaces / ${showKey(String(space))} / Default`, get(spaceEntry, 'Default')],
    [`Displays / ${display}`, get(get(store, 'Displays'), display)],
    ['AllSpacesAndDisplays', get(store, 'AllSpacesAndDisplays')],
  ]
  const hit = candidates.find(([, entry]) => (get(entry, 'Desktop') || {}).type === 'dict')
  if (!hit) return { reason: 'no Desktop entry applies' }
  const choice = items(get(get(get(hit[1], 'Desktop'), 'Content'), 'Choices'))[0]
  const result = { where: hit[0], provider: scalar(get(choice, 'Provider')) }
  if (result.provider !== imageProvider) return { ...result, reason: `Provider is ${show(result.provider)}, not ${imageProvider}` }
  const configuration = (get(choice, 'Configuration') || {}).plist
  const type = scalar(get(configuration, 'type'))
  if (type !== 'imageFile') return { ...result, reason: `Configuration type is ${show(type)}, not imageFile` }
  const relative = scalar(get(get(configuration, 'url'), 'relative'))
  if (typeof relative !== 'string' || !relative.startsWith('file://')) return { ...result, reason: `Configuration url.relative ${show(relative)} is not a file URL` }
  return { ...result, path: decodeURIComponent(relative.replace(/^file:\/\/[^/]*/, '')) }
}

// Mirrors WallpaperSource.resolve, which NotchEngine also uses to tell whether a render is showing.
function describeResolution(screen, spaces, store, context) {
  const out = context.out
  const space = spaces ? spaces.current : undefined
  out.push(`${screen.name}, current Space ${space === undefined ? 'unknown (OpenNotch keys by display alone)' : showKey(space, context.labels)}`)
  let shown
  if (screen.wallpaperIsFile === true && typeof screen.wallpaper === 'string') {
    const kind = classify(screen.wallpaper)
    out.push(`  1. desktopImageURL ${screen.wallpaper}: ${kind.text}`)
    if (kind.kind === 'image' || kind.kind === 'dynamic') shown = { path: screen.wallpaper, kind }
  } else {
    out.push(`  1. desktopImageURL ${show(screen.wallpaper)}: not a file URL`)
  }
  if (!shown) {
    const lookup = store ? storeLookup(store, screen.uuid, space) : { reason: 'no wallpaper store' }
    out.push(`  2. store entry ${show(lookup.where)}, Provider ${show(lookup.provider)}`)
    if (lookup.path) {
      const kind = classify(lookup.path)
      out.push(`     image file ${lookup.path}: ${kind.text}`)
      if (kind.kind === 'image' || kind.kind === 'dynamic') shown = { path: lookup.path, kind }
    } else {
      out.push(`     ${lookup.reason}`)
    }
  }
  if (!shown) out.push('  verdict: shows "This wallpaper type isn\'t supported yet"')
  else if (shown.path.includes(rendersFolder)) out.push(`  verdict: showing an OpenNotch render, ${shown.path}; turning off restores it from applied.json`)
  else out.push(`  verdict: paints ${shown.path}, a ${shown.kind.text}`)
}

function dump(node, depth, label, context) {
  const line = (text) => context.out.push(`${'  '.repeat(depth)}${label === undefined ? '' : `${label}: `}${text}`)
  if (node.type === 'dict') {
    line(`dict (${node.entries.length} keys)`)
    for (const [key, value] of node.entries) dump(value, depth + 1, showKey(key, context.labels), context)
  } else if (node.type === 'array') {
    line(`array (${node.items.length} items)`)
    node.items.forEach((item, i) => dump(item, depth + 1, `[${i}]`, context))
  } else if (node.type === 'data') {
    line(describeData(node))
    if (node.plist) dump(node.plist, depth + 1, undefined, context)
  } else {
    line(`${node.type} ${node.type === 'string' ? JSON.stringify(node.value) : show(node.value)}`)
  }
}
JXA
} 2>&1 | tee "$backup_dir/probe-$stamp.txt"

echo
echo "Saved this report to $backup_dir/probe-$stamp.txt"
