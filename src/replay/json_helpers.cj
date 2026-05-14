package cli.replay

import std.collection.ArrayList
import stdx.encoding.json.*

func jsonGetString(j: JsonValue, key: String): Option<String> {
    match (j.kind()) {
        case JsonKind.JsObject =>
            if (let Some(v) <- j.asObject().get(key)) {
                match (v.kind()) {
                    case JsonKind.JsString => return v.asString().getValue()
                    case _ => ()
                }
            }
        case _ => ()
    }
    return None
}

func jsonGetInt(j: JsonValue, key: String): Option<Int64> {
    match (j.kind()) {
        case JsonKind.JsObject =>
            if (let Some(v) <- j.asObject().get(key)) {
                match (v.kind()) {
                    case JsonKind.JsInt => return v.asInt().getValue()
                    case _ => ()
                }
            }
        case _ => ()
    }
    return None
}

func jsonGetBool(j: JsonValue, key: String): Option<Bool> {
    match (j.kind()) {
        case JsonKind.JsObject =>
            if (let Some(v) <- j.asObject().get(key)) {
                match (v.kind()) {
                    case JsonKind.JsBool => return v.asBool().getValue()
                    case _ => ()
                }
            }
        case _ => ()
    }
    return None
}

func jsonGetValue(j: JsonValue, key: String): Option<JsonValue> {
    match (j.kind()) {
        case JsonKind.JsObject => return j.asObject().get(key)
        case _ => ()
    }
    return None
}

func jsonGetArray(j: JsonValue, key: String): Option<JsonArray> {
    match (j.kind()) {
        case JsonKind.JsObject =>
            if (let Some(v) <- j.asObject().get(key)) {
                match (v.kind()) {
                    case JsonKind.JsArray => return v.asArray()
                    case _ => ()
                }
            }
        case _ => ()
    }
    return None
}

func buildJsonArray(items: Array<JsonValue>): JsonArray {
    let list = ArrayList<JsonValue>()
    for (item in items) {
        list.add(item)
    }
    return JsonArray(list)
}
