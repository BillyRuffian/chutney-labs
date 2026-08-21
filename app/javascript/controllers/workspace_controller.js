import { Controller } from "@hotwired/stimulus"

const WORKSPACE_STORAGE_KEY = "chutney.workspace.v1"
const RULE_SETTINGS_STORAGE_KEY = "chutney.rules.v1"
const MAX_FILE_SIZE = 250 * 1024

export default class extends Controller {
  static targets = [
    "editor", "highlight", "gutter", "filename", "lineCount", "issueList", "issueCount",
    "summary", "lastRun", "runButton", "runLabel", "saveButton", "saveLabel", "fileInput",
    "fileList", "emptyState", "dirtyIndicator", "resultMark", "toast", "docsOverlay",
    "docsTitle", "docsContent", "docsExternalLink", "rulesOverlay", "rulesSearch",
    "rulesCount", "rulesSummary", "ruleToggle", "ruleOption", "ruleGroup", "rulesEmpty"
  ]

  static values = {
    lintUrl: String
  }

  connect() {
    this.issues = []
    this.files = []
    this.currentId = null
    this.dirty = false
    this.lintTimer = null
    this.requestSequence = 0
    this.restoreWorkspace()
    this.restoreRuleSettings()
    this.renderEditor()
    this.lint()
    this.boundShortcut = this.shortcut.bind(this)
    window.addEventListener("keydown", this.boundShortcut)
  }

  disconnect() {
    window.removeEventListener("keydown", this.boundShortcut)
    clearTimeout(this.lintTimer)
  }

  editorChanged() {
    this.markDirty()
    this.renderEditor()
    clearTimeout(this.lintTimer)
    this.lintTimer = setTimeout(() => this.lint(), 700)
  }

  markDirty() {
    this.dirty = true
    this.dirtyIndicatorTarget.hidden = false
    this.saveLabelTarget.textContent = "Save changes"
  }

  markClean() {
    this.dirty = false
    this.dirtyIndicatorTarget.hidden = true
    this.saveLabelTarget.textContent = "Saved"
    setTimeout(() => {
      if (!this.dirty) this.saveLabelTarget.textContent = "Save file"
    }, 1400)
  }

  normalizeFilename() {
    let name = this.filenameTarget.value.trim().replace(/[^\w.-]/g, "-")
    if (!name) name = "untitled.feature"
    if (!name.toLowerCase().endsWith(".feature")) name += ".feature"
    this.filenameTarget.value = name
  }

  renderEditor() {
    const lines = this.editorTarget.value.split("\n")
    const issueLines = new Set(this.issues.map((issue) => Number(issue.line)))
    this.highlightTarget.innerHTML = lines.map((line, index) => {
      const lineNumber = index + 1
      const issue = issueLines.has(lineNumber) ? " has-issue" : ""
      return `<span class="editor-line${issue}" data-line="${lineNumber}">${this.highlightLine(line) || "&#8203;"}</span>`
    }).join("")

    this.gutterTarget.innerHTML = lines.map((_, index) => {
      const lineNumber = index + 1
      const issue = issueLines.has(lineNumber) ? " has-issue" : ""
      return `<span class="gutter-line${issue}">${lineNumber}</span>`
    }).join("")

    this.lineCountTarget.textContent = `${lines.length} ${lines.length === 1 ? "line" : "lines"}`
    this.syncScroll()
  }

  highlightLine(line) {
    const escaped = this.escapeHtml(line)
    if (/^\s*#/.test(line)) return `<span class="tok-comment">${escaped}</span>`
    if (/^\s*@/.test(line)) return escaped.replace(/@[\w:.-]+/g, (tag) => `<span class="tok-tag">${tag}</span>`)

    const keyword = line.match(/^(\s*)(Feature|Rule|Background|Scenario Outline|Scenario|Examples|Given|When|Then|And|But)(:|\b)(.*)$/)
    if (keyword) {
      const [, space, word, punctuation, rest] = keyword
      const kind = ["Given", "When", "Then", "And", "But"].includes(word) ? "step" : "section"
      return `${space}<span class="tok-${kind}">${word}${punctuation}</span>${this.highlightInline(this.escapeHtml(rest))}`
    }

    if (/^\s*\|/.test(line)) {
      return escaped.replace(/\|/g, '<span class="tok-pipe">|</span>')
    }

    return this.highlightInline(escaped)
  }

  highlightInline(escaped) {
    return escaped.replace(/(&lt;[^&]*?&gt;|&quot;.*?&quot;|'.*?')/g, (token) => {
      const klass = token.startsWith("&lt;") ? "tok-variable" : "tok-string"
      return `<span class="${klass}">${token}</span>`
    })
  }

  escapeHtml(value) {
    return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;")
  }

  syncScroll() {
    const x = this.editorTarget.scrollLeft
    const y = this.editorTarget.scrollTop
    this.highlightTarget.style.transform = `translate(${-x}px, ${-y}px)`
    this.gutterTarget.style.transform = `translateY(${-y}px)`
  }

  handleKeydown(event) {
    if (event.key === "Tab") {
      event.preventDefault()
      this.changeIndent(event.shiftKey)
    } else if (event.key === "Enter" && !event.metaKey && !event.ctrlKey && !event.altKey) {
      event.preventDefault()
      this.insertIndentedNewline()
    }
  }

  insertIndentedNewline() {
    const input = this.editorTarget
    const start = input.selectionStart
    const lineStart = input.value.lastIndexOf("\n", start - 1) + 1
    const lineEnd = input.value.indexOf("\n", start)
    const currentLine = input.value.slice(lineStart, lineEnd === -1 ? input.value.length : lineEnd)
    const indentation = currentLine.match(/^[\t ]*/)[0]

    input.setRangeText(`\n${indentation}`, start, input.selectionEnd, "end")
    this.editorChanged()
  }

  changeIndent(outdent) {
    const input = this.editorTarget
    const start = input.selectionStart
    const end = input.selectionEnd

    if (!outdent && start === end) {
      input.setRangeText("  ", start, end, "end")
      this.editorChanged()
      return
    }

    const value = input.value
    const lineStart = value.lastIndexOf("\n", start - 1) + 1
    const effectiveEnd = end > start && value[end - 1] === "\n" ? end - 1 : end
    const followingNewline = value.indexOf("\n", effectiveEnd)
    const lineEnd = followingNewline === -1 ? value.length : followingNewline
    const lines = value.slice(lineStart, lineEnd).split("\n")
    const deltas = []

    const changedLines = lines.map((line) => {
      if (!outdent) {
        deltas.push(2)
        return `  ${line}`
      }

      const indentation = line.match(/^(\t| {1,2})/)
      const removed = indentation ? indentation[0].length : 0
      deltas.push(-removed)
      return line.slice(removed)
    })

    input.setRangeText(changedLines.join("\n"), lineStart, lineEnd, "start")

    if (start === end) {
      const column = start - lineStart
      const newColumn = Math.max(0, column + deltas[0])
      input.setSelectionRange(lineStart + newColumn, lineStart + newColumn)
    } else {
      const newStart = Math.max(lineStart, start + deltas[0])
      const newEnd = end + deltas.reduce((total, delta) => total + delta, 0)
      input.setSelectionRange(newStart, Math.max(newStart, newEnd))
    }

    this.editorChanged()
  }

  shortcut(event) {
    if (event.key === "Escape") {
      if (!this.docsOverlayTarget.hidden) {
        this.closeDocumentation()
        return
      }
      if (!this.rulesOverlayTarget.hidden) {
        this.closeRuleSettings()
        return
      }
    }
    if (!(event.metaKey || event.ctrlKey)) return
    if (event.key.toLowerCase() === "s") {
      event.preventDefault()
      this.save()
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.lint()
    }
  }

  async lint() {
    clearTimeout(this.lintTimer)
    const sequence = ++this.requestSequence
    this.runButtonTarget.disabled = true
    this.runLabelTarget.textContent = "Tasting…"

    try {
      const response = await fetch(this.lintUrlValue, {
        method: "POST",
        headers: this.jsonHeaders(),
        body: JSON.stringify({
          content: this.editorTarget.value,
          filename: this.filenameTarget.value,
          rules: [...this.enabledRules],
          rule_options: this.ruleOptions
        })
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Chutney could not run.")
      if (sequence !== this.requestSequence) return
      this.issues = data.issues
      this.renderReport(data)
      this.renderEditor()
      this.lastRunTarget.textContent = `Checked just now · ${data.duration_ms} ms`
    } catch (error) {
      if (sequence === this.requestSequence) this.showToast(error.message, "error")
    } finally {
      if (sequence === this.requestSequence) {
        this.runButtonTarget.disabled = false
        this.runLabelTarget.textContent = "Run Chutney"
      }
    }
  }

  renderReport(data) {
    const count = data.issues.length
    const clean = count === 0
    this.issueCountTarget.textContent = clean ? "All clear" : `${count} ${count === 1 ? "issue" : "issues"}`
    this.issueCountTarget.className = `issue-count ${clean ? "is-clean" : "has-issues"}`
    this.resultMarkTarget.textContent = clean ? "✓" : "!"
    this.resultMarkTarget.className = `result-mark ${clean ? "is-clean" : "has-issues"}`

    this.summaryTarget.className = `report-summary ${clean ? "is-clean" : "has-issues"}`
    this.summaryTarget.innerHTML = clean ? `
      <div class="summary-orbit"><span>✓</span></div>
      <div><span class="eyebrow">Freshly checked</span><h2>Beautifully seasoned</h2><p>No Chutney issues found. This feature is clear, structured and ready to share.</p></div>
    ` : `
      <div class="summary-orbit"><span>${count}</span></div>
      <div><span class="eyebrow">Needs a little work</span><h2>${data.parse_error ? "Gherkin needs repairing" : "A few flavours are off"}</h2><p>${data.parse_error ? "Fix the syntax issue below, then Chutney can review every rule." : "Select an issue to jump straight to the affected line."}</p></div>
    `

    this.issueListTarget.replaceChildren(...data.issues.map((issue) => this.issueElement(issue)))
  }

  issueElement(issue) {
    const card = document.createElement("article")
    card.className = `issue-card severity-${issue.severity}`
    card.tabIndex = 0
    card.addEventListener("click", () => this.goToLine(issue.line, issue.column))
    card.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault()
        this.goToLine(issue.line, issue.column)
      }
    })

    const top = document.createElement("span")
    top.className = "issue-topline"
    const rule = document.createElement("strong")
    rule.textContent = this.humanize(issue.rule)
    const location = document.createElement("span")
    location.textContent = `Line ${issue.line}:${issue.column}`
    top.append(rule, location)

    const message = document.createElement("span")
    message.className = "issue-message"
    message.textContent = issue.message
    const footer = document.createElement("span")
    footer.className = "issue-footer"
    const identifier = document.createElement("span")
    identifier.textContent = `${issue.type} · ${issue.rule}`
    footer.append(identifier)

    if (issue.documentation_url) {
      const guide = document.createElement("button")
      guide.type = "button"
      guide.className = "issue-doc-link"
      guide.textContent = "Read rule guide →"
      guide.addEventListener("click", (event) => {
        event.stopPropagation()
        this.openDocumentation(issue.documentation_url)
      })
      footer.append(guide)
    }

    card.append(top, message, footer)
    return card
  }

  async openDocumentation(url) {
    this.docsOverlayTarget.hidden = false
    document.body.classList.add("drawer-open")
    this.docsTitleTarget.textContent = "Rule documentation"
    this.docsContentTarget.innerHTML = '<div class="docs-loading">Loading rule guide…</div>'
    this.docsExternalLinkTarget.hidden = true

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Could not load this rule guide.")
      this.docsTitleTarget.textContent = data.title
      this.docsExternalLinkTarget.href = data.external_url
      this.docsExternalLinkTarget.hidden = false
      this.docsContentTarget.replaceChildren(...data.blocks.map((block) => this.documentationBlock(block)))
      this.docsOverlayTarget.querySelector(".docs-close").focus()
    } catch (error) {
      this.docsContentTarget.textContent = error.message
    }
  }

  documentationBlock(block) {
    if (block.type === "heading") {
      const heading = document.createElement("h3")
      heading.textContent = block.content
      return heading
    }

    if (block.type === "code") {
      const pre = document.createElement("pre")
      const code = document.createElement("code")
      code.textContent = block.content
      pre.append(code)
      return pre
    }

    const paragraph = document.createElement("p")
    paragraph.textContent = block.content
    return paragraph
  }

  closeDocumentation(event) {
    event?.stopPropagation()
    this.docsOverlayTarget.hidden = true
    document.body.classList.remove("drawer-open")
  }

  keepDocumentationOpen(event) {
    event.stopPropagation()
  }

  openRuleSettings() {
    this.rulesOverlayTarget.hidden = false
    document.body.classList.add("drawer-open")
    this.rulesSearchTarget.value = ""
    this.filterRules()
    this.rulesSearchTarget.focus()
  }

  closeRuleSettings(event) {
    event?.stopPropagation()
    this.rulesOverlayTarget.hidden = true
    document.body.classList.remove("drawer-open")
  }

  keepRuleSettingsOpen(event) {
    event.stopPropagation()
  }

  openRuleGuideFromSettings(event) {
    this.closeRuleSettings()
    this.openDocumentation(event.currentTarget.dataset.documentationUrl)
  }

  restoreRuleSettings() {
    this.availableRules = this.ruleToggleTargets.map((toggle) => toggle.value)
    this.defaultEnabledRules = this.ruleToggleTargets.filter((toggle) => toggle.dataset.defaultEnabled === "true").map((toggle) => toggle.value)
    this.defaultRuleOptions = this.readRuleOptionsFromControls(true)

    try {
      const stored = localStorage.getItem(RULE_SETTINGS_STORAGE_KEY)
      if (!stored) {
        this.enabledRules = new Set(this.defaultEnabledRules)
        this.ruleOptions = structuredClone(this.defaultRuleOptions)
      } else {
        const settings = JSON.parse(stored)
        if (!settings || !Array.isArray(settings.enabledRules)) throw new Error("Invalid rule settings")
        this.enabledRules = new Set(settings.enabledRules.filter((rule) => this.availableRules.includes(rule)))
        this.ruleOptions = this.normalizeRuleOptions(settings.ruleOptions)
      }
    } catch (error) {
      this.enabledRules = new Set(this.defaultEnabledRules)
      this.ruleOptions = structuredClone(this.defaultRuleOptions)
      this.showToast("Local rule settings could not be read, so Chutney defaults are active.", "error")
    }

    this.syncRuleSettings()
  }

  ruleSettingChanged(event) {
    const enabledRules = new Set(this.enabledRules)
    if (event.currentTarget.checked) {
      enabledRules.add(event.currentTarget.value)
    } else {
      enabledRules.delete(event.currentTarget.value)
    }
    this.updateRuleSettings(enabledRules, event.currentTarget)
  }

  enableAllRules() {
    this.updateRuleSettings(new Set(this.availableRules))
  }

  restoreDefaultRules() {
    this.updateRuleSettings(new Set(this.defaultEnabledRules), null, structuredClone(this.defaultRuleOptions))
  }

  ruleOptionChanged(event) {
    const ruleOptions = structuredClone(this.ruleOptions)
    const input = event.currentTarget
    ruleOptions[input.dataset.ruleName] ||= {}
    ruleOptions[input.dataset.ruleName][input.dataset.optionKey] = this.ruleOptionValue(input)
    this.updateRuleSettings(this.enabledRules, null, ruleOptions)
  }

  updateRuleSettings(enabledRules, changedToggle = null, ruleOptions = this.ruleOptions) {
    try {
      localStorage.setItem(RULE_SETTINGS_STORAGE_KEY, JSON.stringify({ enabledRules: [...enabledRules], ruleOptions }))
    } catch (error) {
      if (changedToggle) changedToggle.checked = !changedToggle.checked
      this.syncRuleSettings()
      this.showToast("This browser could not save your rule settings.", "error")
      return
    }

    this.enabledRules = enabledRules
    this.ruleOptions = ruleOptions
    this.syncRuleSettings()
    this.lint()
  }

  syncRuleSettings() {
    this.ruleToggleTargets.forEach((toggle) => {
      toggle.checked = this.enabledRules.has(toggle.value)
      toggle.closest(".rule-option").classList.toggle("is-enabled", toggle.checked)
    })
    this.ruleOptionTargets.forEach((input) => {
      const value = this.ruleOptions[input.dataset.ruleName]?.[input.dataset.optionKey]
      input.value = this.formatRuleOptionValue(input.dataset.optionType, value)
      input.disabled = !this.enabledRules.has(input.dataset.ruleName)
    })
    this.rulesCountTargets.forEach((count) => {
      count.textContent = `${this.enabledRules.size}/${this.availableRules.length}`
    })
    this.rulesSummaryTarget.textContent = `${this.enabledRules.size} of ${this.availableRules.length} optional checks enabled`
  }

  normalizeRuleOptions(storedOptions) {
    const source = storedOptions && typeof storedOptions === "object" ? storedOptions : {}
    const options = structuredClone(this.defaultRuleOptions)
    this.ruleOptionTargets.forEach((input) => {
      const stored = source[input.dataset.ruleName]?.[input.dataset.optionKey]
      if (stored === undefined) return

      const temporary = document.createElement(input.tagName)
      temporary.dataset.optionType = input.dataset.optionType
      temporary.min = input.min
      temporary.max = input.max
      temporary.value = this.formatRuleOptionValue(input.dataset.optionType, stored)
      options[input.dataset.ruleName][input.dataset.optionKey] = this.ruleOptionValue(temporary)
    })
    return options
  }

  readRuleOptionsFromControls(useDefaults = false) {
    return this.ruleOptionTargets.reduce((options, input) => {
      options[input.dataset.ruleName] ||= {}
      const value = useDefaults ? input.dataset.defaultValue : input.value
      const original = input.value
      input.value = value
      options[input.dataset.ruleName][input.dataset.optionKey] = this.ruleOptionValue(input)
      input.value = original
      return options
    }, {})
  }

  ruleOptionValue(input) {
    switch (input.dataset.optionType) {
      case "integer": {
        const minimum = Number.parseInt(input.min, 10)
        const maximum = Number.parseInt(input.max, 10)
        const value = Number.parseInt(input.value, 10)
        if (!Number.isFinite(value)) return minimum
        return Math.min(maximum, Math.max(minimum, value))
      }
      case "list":
        return [...new Set(input.value.split(/[\n,]/).map((value) => value.trim().replace(/^@/, "")).filter(Boolean))].slice(0, 50)
      case "groups":
        return input.value.split("\n").map((line) => [...new Set(line.split(",").map((value) => value.trim().replace(/^@/, "")).filter(Boolean))].slice(0, 20)).filter((group) => group.length >= 2).slice(0, 20)
      default:
        return input.value.trim().slice(0, 200)
    }
  }

  formatRuleOptionValue(type, value) {
    if (type === "list") return Array.isArray(value) ? value.join(", ") : ""
    if (type === "groups") return Array.isArray(value) ? value.map((group) => Array.isArray(group) ? group.join(", ") : "").filter(Boolean).join("\n") : ""
    return value ?? ""
  }

  filterRules() {
    const query = this.rulesSearchTarget.value.trim().toLowerCase()
    let visibleCount = 0

    this.ruleGroupTargets.forEach((group) => {
      const options = [...group.querySelectorAll(".rule-option")]
      options.forEach((option) => {
        const visible = option.dataset.ruleSearch.includes(query)
        option.classList.toggle("is-hidden", !visible)
        if (visible) visibleCount += 1
      })
      group.hidden = options.every((option) => option.classList.contains("is-hidden"))
    })

    this.rulesEmptyTarget.hidden = visibleCount > 0
  }

  humanize(value) {
    return value.replace(/([a-z])([A-Z])/g, "$1 $2").replace(/^Gherkin Syntax$/, "Gherkin syntax")
  }

  goToLine(line, column = 1) {
    const lines = this.editorTarget.value.split("\n")
    const offset = lines.slice(0, Math.max(0, line - 1)).reduce((sum, value) => sum + value.length + 1, 0)
    this.editorTarget.focus()
    this.editorTarget.setSelectionRange(offset + Math.max(0, column - 1), offset + Math.max(0, column - 1))
    const lineHeight = parseFloat(getComputedStyle(this.editorTarget).lineHeight)
    this.editorTarget.scrollTop = Math.max(0, (line - 3) * lineHeight)
    this.syncScroll()
  }

  save() {
    this.normalizeFilename()
    const content = this.editorTarget.value
    if (new Blob([content]).size > MAX_FILE_SIZE) {
      this.showToast("Feature files must be smaller than 250 KB.", "error")
      return
    }

    const id = this.currentId || this.generateId()
    const file = {
      id,
      name: this.filenameTarget.value,
      content,
      updatedAt: new Date().toISOString()
    }
    const files = [file, ...this.files.filter((entry) => entry.id !== id)]

    try {
      this.persistWorkspace(files, id)
      this.files = files
      this.currentId = id
      this.markClean()
      this.renderFileList()
      this.showToast(`${file.name} saved in this browser`, "success")
    } catch (error) {
      this.showToast("This browser could not save the file. Check that local storage is available and has space.", "error")
      this.saveLabelTarget.textContent = "Save changes"
    }
  }

  openFile(event) {
    if (this.dirty && !window.confirm("Discard your unsaved changes and open this file?")) return
    const file = this.files.find((entry) => entry.id === event.currentTarget.dataset.fileId)
    if (!file) {
      this.showToast("Could not open that feature file from this browser.", "error")
      return
    }

    try {
      this.persistWorkspace(this.files, file.id)
    } catch (error) {
      this.showToast("The file opened, but this browser could not remember it as the active file.", "error")
    }

    this.loadFile(file)
    this.markClean()
    this.renderEditor()
    this.lint()
  }

  newFile() {
    if (this.dirty && !window.confirm("Discard your unsaved changes and create a new file?")) return
    this.startNewFile()
  }

  startNewFile() {
    this.currentId = null
    this.filenameTarget.value = "untitled.feature"
    this.editorTarget.value = "Feature: \n  As a\n  I want to\n  So that\n\n  Scenario: \n    Given \n    When \n    Then "
    this.issues = []
    this.fileListTarget.querySelectorAll(".file-item").forEach((file) => file.classList.remove("is-active"))
    this.markDirty()
    this.renderEditor()
    this.editorTarget.focus()
    this.editorTarget.setSelectionRange(9, 9)
    this.lint()
  }

  deleteFile(event) {
    event.stopPropagation()
    const file = this.files.find((entry) => entry.id === event.currentTarget.dataset.fileId)
    if (!file) {
      this.showToast("Could not find that feature file in this browser.", "error")
      return
    }

    const active = file.id === this.currentId
    const unsavedWarning = active && this.dirty ? " Any unsaved changes will also be lost." : ""
    if (!window.confirm(`Delete "${file.name}" from this browser? This cannot be undone.${unsavedWarning}`)) return

    const files = this.files.filter((entry) => entry.id !== file.id)
    const nextFile = active ? files[0] : this.files.find((entry) => entry.id === this.currentId)

    try {
      this.persistWorkspace(files, nextFile?.id || null)
    } catch (error) {
      this.showToast("This browser could not delete the file. Check that local storage is available.", "error")
      return
    }

    this.files = files
    if (active) {
      if (nextFile) {
        this.loadFile(nextFile)
        this.renderEditor()
        this.lint()
      } else {
        this.startNewFile()
      }
    }

    this.renderFileList()
    this.showToast(`${file.name} deleted from this browser`, "success")
  }

  chooseFile() {
    this.fileInputTarget.click()
  }

  async importFile() {
    const file = this.fileInputTarget.files[0]
    if (!file) return
    if (file.size > 250 * 1024) {
      this.showToast("Feature files must be smaller than 250 KB.", "error")
      return
    }
    if (this.dirty && !window.confirm("Discard your unsaved changes and upload this file?")) return
    this.currentId = null
    this.filenameTarget.value = file.name.toLowerCase().endsWith(".feature") ? file.name : `${file.name}.feature`
    this.editorTarget.value = await file.text()
    this.issues = []
    this.markDirty()
    this.renderEditor()
    this.lint()
    this.fileInputTarget.value = ""
    this.showToast(`${file.name} loaded — save it in this browser to keep it`, "success")
  }

  download() {
    this.normalizeFilename()
    const blob = new Blob([this.editorTarget.value], { type: "text/x-gherkin;charset=utf-8" })
    const link = document.createElement("a")
    link.href = URL.createObjectURL(blob)
    link.download = this.filenameTarget.value
    link.click()
    URL.revokeObjectURL(link.href)
  }

  restoreWorkspace() {
    let workspace
    try {
      workspace = this.readWorkspace()
    } catch (error) {
      this.showToast("Saved browser files could not be read. Local storage may be unavailable or damaged.", "error")
      workspace = { files: [], activeFileId: null }
    }

    this.files = workspace.files
    const activeFile = this.files.find((file) => file.id === workspace.activeFileId) || this.files[0]
    if (activeFile) this.loadFile(activeFile)
    this.renderFileList()
  }

  readWorkspace() {
    const stored = localStorage.getItem(WORKSPACE_STORAGE_KEY)
    if (!stored) return { files: [], activeFileId: null }

    const workspace = JSON.parse(stored)
    if (!workspace || !Array.isArray(workspace.files)) throw new Error("Invalid workspace")

    const files = workspace.files.filter((file) => (
      file &&
      typeof file.id === "string" &&
      typeof file.name === "string" &&
      typeof file.content === "string" &&
      typeof file.updatedAt === "string"
    )).sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))

    return {
      files,
      activeFileId: typeof workspace.activeFileId === "string" ? workspace.activeFileId : null
    }
  }

  persistWorkspace(files, activeFileId) {
    localStorage.setItem(WORKSPACE_STORAGE_KEY, JSON.stringify({ files, activeFileId }))
  }

  loadFile(file) {
    this.currentId = file.id
    this.filenameTarget.value = file.name
    this.editorTarget.value = file.content
    this.issues = []
    this.dirty = false
    this.dirtyIndicatorTarget.hidden = true
    this.saveLabelTarget.textContent = "Save file"
    this.fileListTarget.querySelectorAll(".file-item").forEach((item) => {
      item.classList.toggle("is-active", item.dataset.fileId === file.id)
    })
  }

  renderFileList() {
    this.fileListTarget.querySelectorAll(".file-item").forEach((item) => item.remove())

    this.files.forEach((file) => {
      const item = document.createElement("div")
      item.className = "file-item"
      item.dataset.fileId = file.id
      item.innerHTML = `
        <button class="file-open" type="button" data-action="workspace#openFile">
          <span class="file-icon" aria-hidden="true">F</span>
          <span class="file-details"><strong></strong><small>Saved just now</small></span>
          <span class="file-chevron" aria-hidden="true">›</span>
        </button>
        <button class="file-delete" type="button" data-action="workspace#deleteFile" title="Delete file">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M9 7V4h6v3m3 0-1 13H7L6 7m4 4v5m4-5v5"/></svg>
        </button>
      `
      item.querySelector(".file-open").dataset.fileId = file.id
      item.querySelector(".file-delete").dataset.fileId = file.id
      item.querySelector(".file-delete").ariaLabel = `Delete ${file.name}`
      item.querySelector("strong").textContent = file.name
      item.querySelector("small").textContent = this.savedAtLabel(file.updatedAt)
      item.classList.toggle("is-active", file.id === this.currentId)
      this.fileListTarget.insertBefore(item, this.emptyStateTarget)
    })

    this.emptyStateTarget.hidden = this.files.length > 0
  }

  savedAtLabel(timestamp) {
    const elapsedSeconds = Math.max(0, Math.floor((Date.now() - Date.parse(timestamp)) / 1000))
    if (!Number.isFinite(elapsedSeconds) || elapsedSeconds < 60) return "Saved just now"
    if (elapsedSeconds < 3600) return `Saved ${Math.floor(elapsedSeconds / 60)} min ago`
    if (elapsedSeconds < 86400) return `Saved ${Math.floor(elapsedSeconds / 3600)} hr ago`
    return `Saved ${Math.floor(elapsedSeconds / 86400)} days ago`
  }

  generateId() {
    return crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`
  }

  jsonHeaders() {
    const headers = {
      "Content-Type": "application/json",
      Accept: "application/json"
    }
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken
    return headers
  }

  showToast(message, kind) {
    this.toastTarget.textContent = message
    this.toastTarget.className = `toast is-${kind}`
    this.toastTarget.hidden = false
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => { this.toastTarget.hidden = true }, 3200)
  }
}
