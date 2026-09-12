pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    readonly property string cli: "nori-desktop-settings"

    property var state: ({})
    property var drafts: ({})
    property var pendingPreview: null
    property var requestContext: null
    property var error: null
    property var lastJob: null
    property string operation: ""
    property string stdoutText: ""
    property string stderrText: ""
    property bool busy: false
    property bool stateLoaded: false
    readonly property bool hasDrafts: Object.keys(root.drafts).length > 0

    readonly property var profile: root.state && root.state.profile ? root.state.profile : ({})
    readonly property var components: root.state && root.state.components ? root.state.components : ({})
    readonly property var contracts: root.state && root.state.contracts ? root.state.contracts : ({})
    readonly property var inputSchema: root.contracts && root.contracts.inputSchema
        ? root.contracts.inputSchema
        : null
    readonly property bool schemaLoaded: root.inputSchema !== null
        && root.inputSchema !== undefined
        && typeof root.inputSchema === "object"
        && Object.keys(root.inputSchema).length > 0
    readonly property string schemaError: root.schemaLoaded
        ? ""
        : "The settings service did not return contracts.inputSchema."
    readonly property var activeGeneration: root.state ? root.state.activeGeneration : null
    readonly property var jobs: root.state && Array.isArray(root.state.jobs) ? root.state.jobs : []
    readonly property var componentIds: Object.keys(root.components).sort()
    readonly property var revision: root.profile ? root.profile.revision : undefined

    readonly property string progressMessage: {
        switch (root.operation) {
        case "state":
            return "Refreshing the current profile and active configuration…";
        case "preview":
            return "Resolving the draft and calculating its impact…";
        case "change":
            return "Saving the desired profile revision…";
        case "apply":
            return "Building, activating, and reconciling the configuration…";
        default:
            return "";
        }
    }

    function owns(object, key) {
        return object !== null
            && object !== undefined
            && Object.prototype.hasOwnProperty.call(object, key);
    }

    function displayValue(value) {
        if (value === undefined)
            return "Not reported";
        if (value === null)
            return "None";
        if (typeof value === "string")
            return value;

        try {
            return JSON.stringify(value);
        } catch (exception) {
            return String(value);
        }
    }

    function detailsText(details) {
        if (details === undefined || details === null)
            return "";

        try {
            return JSON.stringify(details, null, 2);
        } catch (exception) {
            return String(details);
        }
    }

    function reportInputError(code, message, details) {
        root.error = {
            code: code,
            message: message,
            details: details
        };
    }

    function sameValue(left, right) {
        if (left === right)
            return true;
        if (left === undefined || right === undefined)
            return false;

        try {
            return JSON.stringify(left) === JSON.stringify(right);
        } catch (exception) {
            return false;
        }
    }

    function draftKey(componentId, settingKey) {
        return componentId + "\u001f" + settingKey;
    }

    function draftEntry(componentId, settingKey) {
        const key = root.draftKey(componentId, settingKey);
        return root.drafts && root.owns(root.drafts, key) ? root.drafts[key] : null;
    }

    function draftValue(componentId, settingKey) {
        const draft = root.draftEntry(componentId, settingKey);
        return draft ? draft.value : root.desiredValue(componentId, settingKey);
    }

    function hasDraft(componentId, settingKey) {
        return root.draftEntry(componentId, settingKey) !== null;
    }

    function discardDraft(componentId, settingKey) {
        const key = root.draftKey(componentId, settingKey);
        if (!root.owns(root.drafts, key))
            return;

        const nextDrafts = ({});
        for (const currentKey of Object.keys(root.drafts)) {
            if (currentKey !== key)
                nextDrafts[currentKey] = root.drafts[currentKey];
        }
        root.drafts = nextDrafts;

        if (root.pendingPreview
            && root.pendingPreview.componentId === componentId
            && root.pendingPreview.settingKey === settingKey)
            root.pendingPreview = null;
    }

    function setDraft(componentId, settingKey, value) {
        if (root.revision === undefined || root.revision === null) {
            root.reportInputError(
                "state_unavailable",
                "Load the current settings state before editing a draft.",
                undefined
            );
            return;
        }

        if (root.sameValue(value, root.desiredValue(componentId, settingKey))) {
            root.discardDraft(componentId, settingKey);
            return;
        }

        const nextDrafts = ({});
        for (const key of Object.keys(root.drafts))
            nextDrafts[key] = root.drafts[key];
        nextDrafts[root.draftKey(componentId, settingKey)] = {
            value: value,
            revision: root.revision
        };
        root.drafts = nextDrafts;

        if (root.pendingPreview
            && root.pendingPreview.componentId === componentId
            && root.pendingPreview.settingKey === settingKey
            && !root.sameValue(root.pendingPreview.value, value))
            root.pendingPreview = null;
    }

    function rebaseDrafts(revision) {
        const rebased = ({});
        for (const key of Object.keys(root.drafts)) {
            rebased[key] = {
                value: root.drafts[key].value,
                revision: revision
            };
        }
        root.drafts = rebased;
        root.pendingPreview = null;
    }

    function replaceState(nextState) {
        const previousRevision = root.revision;
        const nextProfile = nextState && nextState.profile ? nextState.profile : null;
        const nextRevision = nextProfile ? nextProfile.revision : undefined;

        root.state = nextState;
        root.stateLoaded = true;

        if (previousRevision !== undefined && previousRevision !== nextRevision)
            root.rebaseDrafts(nextRevision);
    }

    function previewMatchesCurrent() {
        const preview = root.pendingPreview;
        if (root.error && root.error.code === "revision_conflict")
            return false;
        if (!preview || preview.revision !== root.revision)
            return false;

        const draft = root.draftEntry(preview.componentId, preview.settingKey);
        return draft !== null
            && draft.revision === root.revision
            && root.sameValue(draft.value, preview.value);
    }

    function discardPreview() {
        root.pendingPreview = null;
    }

    function reloadAfterConflict() {
        root.pendingPreview = null;
        return root.refresh();
    }

    function objectForComponent(source, componentId) {
        if (!source)
            return ({});

        const components = source.components ? source.components : source;
        if (!components || !root.owns(components, componentId))
            return ({});

        return components[componentId] || ({});
    }

    function desiredValue(componentId, settingKey) {
        const component = root.objectForComponent(root.profile.components, componentId);
        return root.owns(component, settingKey) ? component[settingKey] : undefined;
    }

    function resolvedValue(componentId, settingKey) {
        const component = root.objectForComponent(root.state.resolved, componentId);
        return root.owns(component, settingKey) ? component[settingKey] : undefined;
    }

    function latestObservedJob() {
        for (const job of root.jobs) {
            if (job && job.observed)
                return job;
        }

        if (root.lastJob && root.lastJob.observed)
            return root.lastJob;

        return null;
    }
    function waybarObservation() {
        const direct = root.state && root.state.observed ? root.state.observed.waybar : null;
        if (direct)
            return direct;

        const job = root.latestObservedJob();
        return job && job.observed ? job.observed.waybar : null;
    }


    function observedValue(componentId, settingKey) {
        const directObservation = root.state ? root.state.observed : null;
        const directComponent = root.objectForComponent(directObservation, componentId);
        if (root.owns(directComponent, settingKey))
            return directComponent[settingKey];

        const generationObservation = root.activeGeneration && root.activeGeneration.observed
            ? root.activeGeneration.observed
            : null;
        const generationComponent = root.objectForComponent(generationObservation, componentId);
        if (root.owns(generationComponent, settingKey))
            return generationComponent[settingKey];

        const waybar = root.waybarObservation();
        if (componentId === "desktop.waybar" && settingKey === "position"
            && waybar && root.owns(waybar, "edge"))
            return waybar.edge;

        return undefined;
    }

    function observedDisplay(componentId, settingKey) {
        const value = root.observedValue(componentId, settingKey);
        if (value !== undefined) {
            if (componentId === "desktop.waybar" && settingKey === "position") {
                const waybar = root.waybarObservation();
                const unit = waybar && waybar.unit ? waybar.unit : "unit status not reported";
                const reason = waybar && waybar.reason ? ": " + waybar.reason : "";
                return root.displayValue(value) + " (" + unit + reason + ")";
            }
            return root.displayValue(value);
        }

        if (root.activeGeneration)
            return "Active generation reported; setting value not observed";

        return "No active generation reported";
    }

    function activeGenerationDisplay() {
        if (!root.activeGeneration)
            return "No active generation reported";

        if (typeof root.activeGeneration === "string")
            return root.activeGeneration;

        if (root.activeGeneration.path)
            return root.activeGeneration.path;

        return root.displayValue(root.activeGeneration);
    }

    function component(componentId) {
        return root.components && root.owns(root.components, componentId)
            ? root.components[componentId]
            : ({});
    }

    function groupRows(component) {
        const settings = component && component.settings ? component.settings : ({});
        const grouped = ({});

        for (const key of Object.keys(settings).sort()) {
            const presentation = settings[key] || ({});
            const name = presentation.group || "Other";
            if (!grouped[name])
                grouped[name] = [];
            grouped[name].push({ key: key, presentation: presentation });
        }

        return Object.keys(grouped).sort().map(name => ({
            name: name,
            settings: grouped[name]
        }));
    }

    function readOnlyRows(component) {
        const fields = component && component.readOnlyFields ? component.readOnlyFields : ({});
        return Object.keys(fields).sort().map(key => ({
            key: key,
            presentation: fields[key]
        }));
    }

    function resolveSchema(schema) {
        let resolved = schema;
        const references = [];

        for (let depth = 0; depth < 16; depth += 1) {
            if (!resolved || typeof resolved !== "object")
                return null;
            if (!root.owns(resolved, "$ref"))
                return resolved;

            const reference = resolved["$ref"];
            if (typeof reference !== "string" || reference.indexOf("#/") !== 0
                || references.indexOf(reference) !== -1)
                return null;
            references.push(reference);

            let target = root.inputSchema;
            for (const token of reference.slice(2).split("/")) {
                const decoded = token.replace(/~1/g, "/").replace(/~0/g, "~");
                target = target && root.owns(target, decoded) ? target[decoded] : undefined;
            }

            if (target === undefined)
                return null;
            resolved = target;
        }

        return null;
    }

    function schemaProperties(schema) {
        const resolved = root.resolveSchema(schema);
        if (!resolved)
            return null;

        const properties = ({});
        let found = false;
        const candidates = [resolved].concat(
            Array.isArray(resolved.allOf) ? resolved.allOf : []
        );
        for (const candidate of candidates) {
            const candidateSchema = candidate === resolved
                ? resolved
                : root.resolveSchema(candidate);
            if (candidateSchema && candidateSchema.properties) {
                for (const key of Object.keys(candidateSchema.properties))
                    properties[key] = candidateSchema.properties[key];
                found = true;
            }
        }

        return found ? properties : null;
    }

    function settingSchema(componentId, settingKey) {
        if (!root.schemaLoaded)
            return null;

        const rootProperties = root.schemaProperties(root.inputSchema);
        if (!rootProperties)
            return null;

        const componentContainer = root.owns(rootProperties, "components")
            ? rootProperties.components
            : root.inputSchema;
        const componentProperties = root.schemaProperties(componentContainer);
        if (!componentProperties || !root.owns(componentProperties, componentId))
            return null;

        const settingProperties = root.schemaProperties(componentProperties[componentId]);
        if (!settingProperties || !root.owns(settingProperties, settingKey))
            return null;

        return root.resolveSchema(settingProperties[settingKey]);
    }

    function enumContract(componentId, settingKey) {
        let schema = root.settingSchema(componentId, settingKey);
        if (!schema) {
            return {
                values: [],
                error: "The generated input schema does not resolve this enum setting."
            };
        }

        const branches = []
            .concat(Array.isArray(schema.oneOf) ? schema.oneOf : [])
            .concat(Array.isArray(schema.anyOf) ? schema.anyOf : []);
        if (branches.length > 0) {
            return {
                values: [],
                error: "The generated enum has multiple alternative schemas and cannot be edited safely."
            };
        }

        const allOf = Array.isArray(schema.allOf) ? schema.allOf : [];
        if (allOf.length > 1) {
            return {
                values: [],
                error: "The generated enum has multiple composed schemas and cannot be edited safely."
            };
        }
        if (allOf.length === 1) {
            schema = root.resolveSchema(allOf[0]);
            if (!schema) {
                return {
                    values: [],
                    error: "The generated enum references an unresolved schema."
                };
            }
        }

        if (!Array.isArray(schema.enum) || schema.enum.length === 0) {
            return {
                values: [],
                error: "The generated enum does not expose one non-empty enum value set."
            };
        }

        for (const value of schema.enum) {
            if (typeof value !== "string") {
                return {
                    values: [],
                    error: "The generated enum contains a non-string value and cannot be edited safely."
                };
            }
        }

        return {
            values: schema.enum,
            error: ""
        };
    }

    function enumValues(componentId, settingKey) {
        return root.enumContract(componentId, settingKey).values;
    }

    function enumError(componentId, settingKey) {
        return root.enumContract(componentId, settingKey).error;
    }

    function parseControlValue(control, text) {
        if (control === "text")
            return { ok: true, value: text };

        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (exception) {
            return {
                ok: false,
                message: "Enter valid JSON for this setting.",
                details: exception.toString()
            };
        }

        if (control === "number" && (typeof parsed !== "number" || !isFinite(parsed))) {
            return {
                ok: false,
                message: "Enter a finite JSON number for this setting.",
                details: text
            };
        }

        if (control === "list" && !Array.isArray(parsed)) {
            return {
                ok: false,
                message: "Enter a JSON array for this setting.",
                details: text
            };
        }

        return { ok: true, value: parsed };
    }

    function jobRows() {
        const rows = root.jobs.slice();
        if (root.lastJob && !rows.some(job => job && job.id === root.lastJob.id))
            rows.unshift(root.lastJob);
        return rows;
    }

    function jobStatus(job) {
        return job && job.status ? job.status : "status not reported";
    }

    function jobObservation(job) {
        if (!job || !job.observed)
            return "Observation pending";
        return root.displayValue(job.observed);
    }

    function request(command, operationName, context) {
        if (root.busy || commandProcess.running) {
            root.reportInputError(
                "request_in_progress",
                "Wait for the current settings request to finish.",
                { operation: root.operation }
            );
            return false;
        }

        root.error = null;
        root.operation = operationName;
        root.requestContext = context || null;
        root.stdoutText = "";
        root.stderrText = "";
        root.busy = true;
        commandProcess.command = command;
        commandProcess.running = true;
        return true;
    }

    function refresh() {
        return root.request([root.cli, "state", "--json"], "state", null);
    }

    function previewDraft(componentId, settingKey) {
        const draft = root.draftEntry(componentId, settingKey);
        if (!draft) {
            root.reportInputError(
                "draft_unavailable",
                "Edit a setting before requesting its preview.",
                { componentId: componentId, settingKey: settingKey }
            );
            return false;
        }
        if (draft.revision !== root.revision) {
            root.reportInputError(
                "stale_draft",
                "Refresh and preview this draft again before saving it.",
                { draftRevision: draft.revision, currentRevision: root.revision }
            );
            return false;
        }

        return root.request([
            root.cli,
            "preview",
            componentId,
            settingKey,
            JSON.stringify(draft.value),
            "--expected-revision",
            String(draft.revision),
            "--json"
        ], "preview", {
            componentId: componentId,
            settingKey: settingKey,
            value: draft.value,
            revision: draft.revision
        });
    }

    function change(componentId, settingKey, value, expectedRevision) {
        const revision = expectedRevision === undefined ? root.revision : expectedRevision;
        if (revision === undefined || revision === null) {
            root.reportInputError(
                "state_unavailable",
                "Load the current settings state before changing a setting.",
                undefined
            );
            return false;
        }

        return root.request([
            root.cli,
            "change",
            componentId,
            settingKey,
            JSON.stringify(value),
            "--expected-revision",
            String(revision),
            "--json"
        ], "change", {
            componentId: componentId,
            settingKey: settingKey,
            value: value,
            revision: revision
        });
    }

    function commitPreview() {
        if (!root.previewMatchesCurrent()) {
            root.reportInputError(
                "stale_preview",
                "The draft or profile revision changed after this preview. Preview again before saving.",
                root.pendingPreview
            );
            return false;
        }

        const preview = root.pendingPreview;
        return root.change(
            preview.componentId,
            preview.settingKey,
            preview.value,
            preview.revision
        );
    }

    function apply() {
        if (root.hasDrafts) {
            root.reportInputError(
                "draft_pending",
                "Save or discard every local draft before applying the profile.",
                undefined
            );
            return false;
        }
        if (root.revision === undefined || root.revision === null) {
            root.reportInputError(
                "state_unavailable",
                "Load the current settings state before applying it.",
                undefined
            );
            return false;
        }

        return root.request([
            root.cli,
            "apply",
            "--expected-revision",
            String(root.revision),
            "--json"
        ], "apply", null);
    }

    function responsePayload() {
        const body = root.stdoutText.trim().length > 0
            ? root.stdoutText.trim()
            : root.stderrText.trim();
        if (body.length === 0)
            return null;

        try {
            return JSON.parse(body);
        } catch (exception) {
            return null;
        }
    }

    function failureFor(payload, exitCode) {
        if (payload && payload.error && typeof payload.error.code === "string")
            return payload.error;

        const details = {
            exitCode: exitCode,
            stdout: root.stdoutText,
            stderr: root.stderrText
        };
        return {
            code: "cli_failure",
            message: "The settings CLI did not return a typed JSON failure.",
            details: details
        };
    }

    function completeProcess(exitCode) {
        const completedOperation = root.operation;
        const context = root.requestContext;
        const payload = root.responsePayload();
        let success = false;

        if (payload && payload.ok === true) {
            if (completedOperation === "state" || completedOperation === "change") {
                if (root.owns(payload, "state")) {
                    root.replaceState(payload.state);
                    if (completedOperation === "change") {
                        if (context)
                            root.discardDraft(context.componentId, context.settingKey);
                        root.pendingPreview = null;
                    }
                    success = true;
                } else {
                    root.reportInputError(
                        "invalid_cli_response",
                        "The settings CLI succeeded without returning state.",
                        payload
                    );
                }
            } else if (completedOperation === "preview") {
                if (!root.owns(payload, "preview")) {
                    root.reportInputError(
                        "invalid_cli_response",
                        "The settings CLI succeeded without returning a preview.",
                        payload
                    );
                } else if (!context) {
                    root.reportInputError(
                        "invalid_cli_response",
                        "The settings CLI preview cannot be matched to a local draft.",
                        payload
                    );
                } else {
                    const draft = root.draftEntry(context.componentId, context.settingKey);
                    if (context.revision === root.revision
                        && draft
                        && draft.revision === root.revision
                        && root.sameValue(draft.value, context.value)) {
                        root.pendingPreview = {
                            componentId: context.componentId,
                            settingKey: context.settingKey,
                            value: context.value,
                            revision: context.revision,
                            preview: payload.preview
                        };
                        success = true;
                    } else {
                        root.reportInputError(
                            "stale_preview",
                            "The draft changed while its preview was being calculated.",
                            context
                        );
                    }
                }
            } else if (completedOperation === "apply") {
                if (root.owns(payload, "job")) {
                    root.lastJob = payload.job;
                    success = true;
                } else {
                    root.reportInputError(
                        "invalid_cli_response",
                        "The settings CLI succeeded without returning an apply job.",
                        payload
                    );
                }
            }
        } else {
            root.error = root.failureFor(payload, exitCode);
        }

        root.busy = false;
        root.operation = "";
        root.requestContext = null;

        if (success && (completedOperation === "change" || completedOperation === "apply"))
            Qt.callLater(function() { root.refresh(); });
    }


    Process {
        id: commandProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.stdoutText = text
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.stderrText = text
        }
        onExited: function(exitCode, exitStatus) {
            Qt.callLater(function() { root.completeProcess(exitCode); });
        }
    }

    Component.onCompleted: root.refresh()

    Component.onDestruction: {
        if (commandProcess.running)
            commandProcess.running = false;
    }
}
