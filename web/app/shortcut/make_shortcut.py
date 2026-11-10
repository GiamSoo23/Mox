#!/usr/bin/env python3
"""Builds the "Send to Mox" iPhone shortcut (#27).

    python3 -I web/app/shortcut/make_shortcut.py OUT.shortcut   # unsigned
    shortcuts sign --mode anyone --input OUT.shortcut --output web/app/Send-to-Mox.shortcut

It appears under Share in Photos, Files, Safari and other apps. On install
it asks for the setup code from Mox for iPhone (JSON: the mox-send URL, the
publishable key, the Mox user and this iPhone's device id). Running it sends
the first shared item to the mox-send Edge Function in one request: text
and links as text, everything else as a file.
"""
import plistlib
import sys
import uuid

OBJ = "￼"  # where a variable sits inside a text field


def text(value):
    return {"Value": {"string": value}, "WFSerializationType": "WFTextTokenString"}


def output(action_uuid, name):
    return {"OutputUUID": action_uuid, "Type": "ActionOutput", "OutputName": name}


def named(variable):
    return {"Type": "Variable", "VariableName": variable}


def in_text(attachment):
    return {"Value": {"string": OBJ, "attachmentsByRange": {"{0, 1}": attachment}},
            "WFSerializationType": "WFTextTokenString"}


def ref(attachment):
    return {"Value": attachment, "WFSerializationType": "WFTextTokenAttachment"}


def fields(items):
    return {"Value": {"WFDictionaryFieldValueItems": items}, "WFSerializationType": "WFDictionaryFieldValue"}


def field(key, value, item_type=0):
    return {"WFItemType": item_type, "WFKey": text(key), "WFValue": value}


actions = []


def act(identifier, **parameters):
    action_uuid = str(uuid.uuid4()).upper()
    parameters.setdefault("UUID", action_uuid)
    actions.append({"WFWorkflowActionIdentifier": f"is.workflow.actions.{identifier}",
                    "WFWorkflowActionParameters": parameters})
    return action_uuid


def condition(subject, mode, group, equals=None):
    parameters = {"GroupingIdentifier": group, "WFControlFlowMode": mode}
    if mode == 0:
        parameters.update({"WFCondition": 4, "WFConditionalActionString": equals,
                           "WFInput": {"Type": "Variable", "Variable": ref(subject)}})
    return act("conditional", **parameters)


# 0: the setup code, filled in by the install question.
setup = act("gettext", WFTextActionText="")
config = act("detect.dictionary", WFInput=ref(output(setup, "Text")))
values = {}
for key in ("url", "key", "email", "password", "device"):
    values[key] = act("getvalueforkey", WFDictionaryKey=key, WFInput=ref(output(config, "Dictionary")),
                      CustomOutputName=key)

# The first shared item, and whether it's text (or a link) or a file.
item = act("getitemfromlist", WFInput=ref({"Type": "ExtensionInput"}), WFItemSpecifier="First Item")
kind = act("getitemtype", WFInput=ref(output(item, "Item from List")))
default = act("gettext", WFTextActionText="file")
act("setvariable", WFVariableName="mode", WFInput=ref(output(default, "Text")))
for type_name in ("Text", "URL", "Rich Text"):
    group = str(uuid.uuid4()).upper()
    condition(output(kind, "Type"), 0, group, type_name)
    marker = act("gettext", WFTextActionText="text")
    act("setvariable", WFVariableName="mode", WFInput=ref(output(marker, "Text")))
    condition(None, 2, group)

headers = fields([field(f"x-mox-{key}", in_text(output(values[key], key)))
                  for key in ("key", "email", "password", "device")])
url = in_text(output(values["url"], "url"))
shared = output(item, "Item from List")

group = str(uuid.uuid4()).upper()
condition(named("mode"), 0, group, "text")
act("downloadurl", WFURL=url, WFHTTPMethod="POST", WFHTTPBodyType="Form", ShowHeaders=True,
    WFHTTPHeaders=headers, WFFormValues=fields([field("text", in_text(shared))]))
condition(None, 1, group)
act("downloadurl", WFURL=url, WFHTTPMethod="POST", WFHTTPBodyType="Form", ShowHeaders=True,
    WFHTTPHeaders=headers, WFFormValues=fields([field("file", ref(shared), item_type=5)]))
result = condition(None, 2, group)

# mox-send always answers {"message": "..."}: show it.
message = act("getvalueforkey", WFDictionaryKey="message", WFInput=ref(output(result, "If Result")))
act("notification", WFNotificationActionTitle="Mox",
    WFNotificationActionBody=in_text(output(message, "Dictionary Value")))

workflow = {
    "WFWorkflowClientVersion": "2605.0.5",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 59446},
    "WFWorkflowTypes": ["ActionExtension"],
    "WFWorkflowInputContentItemClasses": [
        "WFImageContentItem", "WFPhotoMediaContentItem", "WFAVAssetContentItem", "WFGenericFileContentItem",
        "WFPDFContentItem", "WFStringContentItem", "WFRichTextContentItem", "WFURLContentItem",
    ],
    "WFWorkflowHasShortcutInputVariables": True,
    "WFWorkflowOutputContentItemClasses": [],
    "WFQuickActionSurfaces": [],
    "WFWorkflowImportQuestions": [{
        "ActionIndex": 0, "Category": "Parameter", "DefaultValue": "", "ParameterKey": "WFTextActionText",
        "Text": "Paste the setup code from Mox for iPhone (Send from any app → Copy setup code).",
    }],
    "WFWorkflowActions": actions,
}

with open(sys.argv[1], "wb") as handle:
    plistlib.dump(workflow, handle, fmt=plistlib.FMT_BINARY)
print(f"wrote {sys.argv[1]} ({len(actions)} actions)")
