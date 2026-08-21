import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "editor", "highlight", "gutter", "filename", "lineCount", "issueList", "issueCount",
    "summary", "lastRun", "runButton", "runLabel", "saveButton", "saveLabel", "fileInput",
    "fileList", "emptyState", "dirtyIndicator", "resultMark", "toast", "docsOverlay",
    "docsTitle", "docsContent", "docsExternalLink"
  ]

  static values = {
    lintUrl: String,
    createUrl: String,
    currentId: String
  }

  connect() {
    this.issues = []
    this.dirty = false
    this.lintTimer = null
    this.requestSequence = 0
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
      const input = this.editorTarget
      const start = input.selectionStart
      input.setRangeText("  ", start, input.selectionEnd, "end")
      this.editorChanged()
    }
  }

  shortcut(event) {
    if (event.key === "Escape" && !this.docsOverlayTarget.hidden) {
      this.closeDocumentation()
      return
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
        body: JSON.stringify({ content: this.editorTarget.value, filename: this.filenameTarget.value })
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

  async save() {
    this.normalizeFilename()
    this.saveButtonTarget.disabled = true
    this.saveLabelTarget.textContent = "Saving…"
    const persisted = Boolean(this.currentIdValue)
    const url = persisted ? `${this.createUrlValue}/${this.currentIdValue}` : this.createUrlValue

    try {
      const response = await fetch(url, {
        method: persisted ? "PATCH" : "POST",
        headers: this.jsonHeaders(),
        body: JSON.stringify({ feature_file: { name: this.filenameTarget.value, content: this.editorTarget.value } })
      })
      const data = await response.json()
      if (!response.ok) throw new Error((data.errors || ["Could not save this file."]).join(" "))
      this.currentIdValue = String(data.id)
      this.markClean()
      this.upsertFileItem(data)
      this.showToast(`${data.name} saved`, "success")
    } catch (error) {
      this.showToast(error.message, "error")
      this.saveLabelTarget.textContent = "Save changes"
    } finally {
      this.saveButtonTarget.disabled = false
    }
  }

  async openFile(event) {
    if (this.dirty && !window.confirm("Discard your unsaved changes and open this file?")) return
    const item = event.currentTarget
    try {
      const response = await fetch(`${this.createUrlValue}/${item.dataset.fileId}`, { headers: { Accept: "application/json" } })
      const data = await response.json()
      if (!response.ok) throw new Error("Could not open that feature file.")
      this.currentIdValue = String(data.id)
      this.filenameTarget.value = data.name
      this.editorTarget.value = data.content
      this.issues = []
      this.fileListTarget.querySelectorAll(".file-item").forEach((file) => file.classList.toggle("is-active", file === item))
      this.markClean()
      this.renderEditor()
      this.lint()
    } catch (error) {
      this.showToast(error.message, "error")
    }
  }

  newFile() {
    if (this.dirty && !window.confirm("Discard your unsaved changes and create a new file?")) return
    this.currentIdValue = ""
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
    this.currentIdValue = ""
    this.filenameTarget.value = file.name.toLowerCase().endsWith(".feature") ? file.name : `${file.name}.feature`
    this.editorTarget.value = await file.text()
    this.issues = []
    this.markDirty()
    this.renderEditor()
    this.lint()
    this.fileInputTarget.value = ""
    this.showToast(`${file.name} loaded — save it to keep it here`, "success")
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

  upsertFileItem(file) {
    this.emptyStateTarget.hidden = true
    let item = this.fileListTarget.querySelector(`[data-file-id="${file.id}"]`)
    if (!item) {
      item = document.createElement("button")
      item.type = "button"
      item.className = "file-item"
      item.dataset.fileId = file.id
      item.dataset.action = "workspace#openFile"
      item.innerHTML = '<span class="file-icon" aria-hidden="true">F</span><span class="file-details"><strong></strong><small>Saved just now</small></span><span class="file-chevron" aria-hidden="true">›</span>'
      this.fileListTarget.prepend(item)
    }
    item.querySelector("strong").textContent = file.name
    item.querySelector("small").textContent = "Saved just now"
    this.fileListTarget.querySelectorAll(".file-item").forEach((entry) => entry.classList.toggle("is-active", entry === item))
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
