"""Phone icons - NATIVE variant (lucide-react-native) for Android / iOS builds.

Same `Icon` API and keys as `Icon.jac`; the compiler checks the signatures match.
"""

import from "lucide-react-native" {
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
