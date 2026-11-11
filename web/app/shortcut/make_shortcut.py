#!/usr/bin/env python3
"""Builds the "Send to Mox" iPhone shortcut (#27), for reference.

    python3 -I web/app/shortcut/make_shortcut.py OUT.shortcut

The published shortcut is the iCloud link in Mox for iPhone. It was made by
importing this file into Shortcuts on a Mac (after `shortcuts sign --mode
anyone`) and sharing it from there, because iPhone wouldn't add the signed
file directly.

It sends the shared file itself as the request body to the mox-send Edge
Function, with the setup code from Mox for iPhone in one header
(x-mox-setup) and the file's name in x-mox-name. The first action is an
empty Text: each person pastes their own setup code there.

Lessons from building it: a form field with WFItemType 5 crashes Shortcuts
(it isn't a valid item type), so the body is the raw file instead.
"""
import plistlib
import sys
import uuid
OBJ = "￼"
def text(v): return {"Value": {"string": v}, "WFSerializationType": "WFTextTokenString"}
def output(u, name): return {"OutputUUID": u, "Type": "ActionOutput", "OutputName": name}
def in_text(att): return {"Value": {"string": OBJ, "attachmentsByRange": {"{0, 1}": att}}, "WFSerializationType": "WFTextTokenString"}
def ref(att): return {"Value": att, "WFSerializationType": "WFTextTokenAttachment"}
def fields(items): return {"Value": {"WFDictionaryFieldValueItems": items}, "WFSerializationType": "WFDictionaryFieldValue"}
def field(k, v, t=0): return {"WFItemType": t, "WFKey": text(k), "WFValue": v}
actions = []
def act(ident, **p):
    u = str(uuid.uuid4()).upper(); p.setdefault("UUID", u)
    actions.append({"WFWorkflowActionIdentifier": f"is.workflow.actions.{ident}", "WFWorkflowActionParameters": p})
    return u
code = act("gettext", WFTextActionText="")
config = act("detect.dictionary", WFInput=ref(output(code, "Text")))
url = act("getvalueforkey", WFDictionaryKey="url", WFInput=ref(output(config, "Dictionary")))
name = act("properties.files", WFInput=ref({"Type": "ExtensionInput"}), WFContentItemPropertyName="Name")
sent = act("downloadurl", WFURL=in_text(output(url, "Dictionary Value")), WFHTTPMethod="POST", WFHTTPBodyType="File",
           ShowHeaders=True, WFRequestVariable=ref({"Type": "ExtensionInput"}),
           WFHTTPHeaders=fields([field("x-mox-setup", in_text(output(code, "Text"))),
                                 field("x-mox-name", in_text(output(name, "Name")))]))
msg = act("getvalueforkey", WFDictionaryKey="message", WFInput=ref(output(sent, "Contents of URL")))
act("notification", WFNotificationActionTitle="Mox", WFNotificationActionBody=in_text(output(msg, "Dictionary Value")))
types = ["WFImageContentItem", "WFPhotoMediaContentItem", "WFAVAssetContentItem", "WFGenericFileContentItem", "WFPDFContentItem"]
wf = {"WFWorkflowClientVersion": "2605.0.5", "WFWorkflowMinimumClientVersion": 900, "WFWorkflowMinimumClientVersionString": "900",
      "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 59446},
      "WFWorkflowTypes": ["ActionExtension"], "WFWorkflowInputContentItemClasses": types,
      "WFWorkflowHasShortcutInputVariables": True, "WFWorkflowOutputContentItemClasses": [], "WFQuickActionSurfaces": [],
      "WFWorkflowImportQuestions": [], "WFWorkflowActions": actions}
open(sys.argv[1], "wb").write(plistlib.dumps(wf, fmt=plistlib.FMT_BINARY))
print(len(actions), "actions")
