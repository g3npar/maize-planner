"""Phone icons - WEB variant (lucide-react), used when the phone UI renders in a browser.

`Icon.native.jac` is picked for Android / iOS builds. Keep the keys identical.
"""

import from "lucide-react" {
    House,
    ListTodo,
    BookOpen,
    Sparkles,
    User,
    Check,
    Plus,
    RefreshCw,
    ExternalLink,
    Trash2,
    X,
    Clock,
    MapPin,
    LogOut,
    AlertTriangle,
    Play,
    Wand2
}

glob LUCIDE: dict[str, any] = {
         "home": House,
         "tasks": ListTodo,
         "classes": BookOpen,
         "plan": Sparkles,
         "me": User,
         "check": Check,
         "plus": Plus,
         "refresh": RefreshCw,
         "open": ExternalLink,
         "trash": Trash2,
         "close": X,
         "clock": Clock,
         "pin": MapPin,
         "logout": LogOut,
         "alert": AlertTriangle,
         "start": Play,
         "magic": Wand2
     };

def:pub Icon(name: str, size: int, color: str) -> JsxElement {
    Glyph = LUCIDE[name];
    <Glyph size={size} color={color} strokeWidth={2.2}/>
}
