"""Reusable phone pieces: chips, task rows, the tab bar, the error banner."""

import from "@jac/mobui" { View, Text, Pressable }
import from core.planner { AssignmentView }
import from core.state { source_label, source_color, urgency_color, progress_of }
import from .theme { C, styles }
import from .Icon { Icon }

obj PhoneTab {
    has key: str,
        icon: str,
        label: str;
}

glob PHONE_TABS: list[PhoneTab] = [
         PhoneTab(key="today", icon="home", label="Today"),
         PhoneTab(key="tasks", icon="tasks", label="Tasks"),
         PhoneTab(key="classes", icon="classes", label="Classes"),
         PhoneTab(key="plan", icon="plan", label="Plan"),
         PhoneTab(key="me", icon="me", label="Me")
     ];

def tint(color: str) -> str {
    return color + "22";
}

def:pub Chip(label: str, color: str) -> JsxElement {
    <View style={[styles.chip, {"backgroundColor": tint(color)}]}>
        <Text style={[styles.chipText, {"color": color}]}>{label}</Text>
    </View>
}

def:pub SectionHeader(title: str, count: int, color: str) -> JsxElement {
    <View style={styles.row}>
        <View style={{"width": 8, "height": 8, "borderRadius": 4, "backgroundColor": color}}/>
        <Text style={styles.sectionTitle}>{title.upper() + "  " + str(count)}</Text>
    </View>
}

def:pub TaskRow(
    a: AssignmentView,
    onToggle: Callable[[AssignmentView], None],
    onOpen: Callable[[AssignmentView], None],
    busy: bool = False
) -> JsxElement {
    done = a.status == "done";
    steps = progress_of(a);
    <Pressable style={styles.task} onPress={lambda { onOpen(a); }}>
        <Pressable
            accessibilityRole="checkbox"
            accessibilityLabel={"Mark " + a.title + (" not done" if done else " done")}
            disabled={busy}
            style={[styles.check, {"borderColor": a.course_color, "backgroundColor": a.course_color if done else "transparent"}]}
            onPress={lambda { onToggle(a); }}
        >
            {(<Icon name="check" size={14} color={C.white}/>) if done else <View/>}
        </Pressable>
        <View style={{"flex": 1, "gap": 4}}>
            <Text style={styles.taskDone if done else styles.taskTitle} numberOfLines={2}>
                {("!! " if a.priority >= 3 else "") + a.title}
            </Text>
            <View style={styles.row}>
                <Chip label={a.course_code} color={a.course_color}/>
                <Chip label={source_label(a.source)} color={source_color(a.source)}/>
                {(<Text style={styles.small}>{steps}</Text>) if steps else <View/>}
            </View>
        </View>
        <View style={{"alignItems": "flex-end", "gap": 2, "maxWidth": 110}}>
            <Text style={styles.due}>{a.due_label}</Text>
            <Text style={[styles.dueIn, {"color": urgency_color(a.urgency)}]}>{a.due_in}</Text>
        </View>
    </Pressable>
}

def:pub TabBar(active: str, onPick: Callable[[str], None], overdue: int) -> JsxElement {
    <View style={styles.tabBar}>
        {for t in PHONE_TABS {
            <Pressable
                key={t.key}
                accessibilityRole="button"
                accessibilityLabel={t.label}
                style={styles.tabItem}
                onPress={lambda { onPick(t.key); }}
            >
                <View>
                    <Icon name={t.icon} size={22} color={C.primary if active == t.key else C.muted}/>
                    {(<View style={{"position": "absolute", "top": -3, "right": -8, "backgroundColor": C.danger, "borderRadius": 8, "paddingHorizontal": 4}}>
                        <Text style={{"color": C.white, "fontSize": 10, "fontWeight": "bold"}}>{str(overdue)}</Text>
                    </View>) if t.key == "today" and overdue > 0 else <View/>}
                </View>
                <Text style={styles.tabLabelOn if active == t.key else styles.tabLabel}>{t.label}</Text>
            </Pressable>
        }}
    </View>
}

def:pub Banner(message: str, color: str, onClose: Callable[[], None]) -> JsxElement {
    <View style={[styles.banner, {"backgroundColor": color}]}>
        <Text style={styles.bannerText}>{message}</Text>
        <Pressable accessibilityLabel="Dismiss" onPress={lambda { onClose(); }}>
            <Icon name="close" size={16} color={C.white}/>
        </Pressable>
    </View>
}

def:pub Seg(options: list[tuple[str, str]], value: str, onPick: Callable[[str], None]) -> JsxElement {
    <View style={styles.seg}>
        {for (key, label) in options {
            <Pressable key={key} style={[styles.segItem, styles.segOn if value == key else {}]} onPress={lambda { onPick(key); }}>
                <Text style={styles.segTextOn if value == key else styles.segText}>{label}</Text>
            </Pressable>
        }}
    </View>
}
