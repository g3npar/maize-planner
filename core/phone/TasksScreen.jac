"""Phone Tasks: natural-language quick add, filters, and a detail sheet."""

import from "@jac/mobui" { View, Text, TextInput, ScrollView, Pressable, Modal, Linking, ActivityIndicator }
import from core.planner { AssignmentView }
import from core.state { Planner, source_label, source_color, urgency_color }
import from .theme { C, styles }
import from .parts { TaskRow, Seg, Chip }
import from .Icon { Icon }

def step_done(a: AssignmentView, i: int) -> bool {
    return i < len(a.subtasks_done) and bool(a.subtasks_done[i]);
}

def:pub TaskSheet(p: Planner, a: AssignmentView, onClose: Callable[[], None]) -> JsxElement {
    has confirm: bool = False;
    done = a.status == "done";

    async def remove -> None {
        await p.deleteAssignment(a.id);
        onClose();
    }

    <View style={styles.sheet}>
        <View style={styles.between}>
            <Chip label={a.course_code} color={a.course_color}/>
            <Pressable accessibilityLabel="Close" onPress={lambda { onClose(); }}>
                <Icon name="close" size={22} color={C.muted}/>
            </Pressable>
        </View>
        <Text style={[styles.h1, {"fontSize": 21}]}>{a.title}</Text>
        <View style={styles.row}>
            <Chip label={source_label(a.source)} color={source_color(a.source)}/>
            <Text style={[styles.small, {"color": urgency_color(a.urgency), "fontWeight": "bold"}]}>{a.due_label + ("  ·  " + a.due_in if a.due_in else "")}</Text>
        </View>
        {(<Text style={styles.sub}>{a.notes}</Text>) if a.notes else <View/>}
        {(<Text style={styles.small}>{"Score: " + f"{a.score:g}" + " / " + f"{a.points:g}"}</Text>) if a.score is not None else <View/>}
        <View style={styles.row}>
            <Pressable style={[styles.button, {"flex": 1, "backgroundColor": C.success if not done else C.muted}]} onPress={lambda { p.toggleDone(a); }}>
                <Icon name="check" size={16} color={C.white}/>
                <Text style={styles.buttonText}>{"Mark not done" if done else "Mark done"}</Text>
            </Pressable>
            {(<Pressable style={styles.ghostButton} onPress={lambda { p.setStatus(a.id, "doing"); }}>
                <Icon name="start" size={15} color={C.text}/>
                <Text style={styles.ghostText}>Start</Text>
            </Pressable>) if a.status == "todo" else <View/>}
        </View>
        {(<Pressable style={styles.ghostButton} onPress={lambda { Linking.openURL(a.url); }}>
            <Icon name="open" size={15} color={C.primary}/>
            <Text style={styles.ghostText}>{"Open in " + source_label(a.source)}</Text>
        </Pressable>) if a.url else <View/>}
        <View style={styles.between}>
            <Text style={styles.sectionTitle}>STEPS</Text>
            <Pressable style={styles.ghostButton} disabled={p.busyId == a.id} onPress={lambda { p.breakdown(a.id); }}>
                {(<ActivityIndicator size="small" color={C.primary}/>) if p.busyId == a.id else (<Icon name="magic" size={14} color={C.primary}/>)}
                <Text style={styles.ghostText}>Break it down</Text>
            </Pressable>
        </View>
        <ScrollView style={{"maxHeight": 220}}>
            {(<Text style={styles.small}>No steps yet.</Text>) if not a.subtasks else <View/>}
            {for (i, step) in enumerate(a.subtasks) {
                <Pressable key={str(i) + step} style={styles.step} onPress={lambda { p.toggleSubtask(a.id, i); }}>
                    <View style={[styles.box, styles.boxOn if step_done(a, i) else {}]}>
                        {(<Icon name="check" size={12} color={C.white}/>) if step_done(a, i) else <View/>}
                    </View>
                    <Text style={styles.taskDone if step_done(a, i) else [styles.taskTitle, {"fontWeight": "normal"}]}>{step}</Text>
                </Pressable>
            }}
        </ScrollView>
        <Pressable style={styles.ghostButton} onPress={lambda { if confirm { remove(); } else { confirm = True; } }}>
            <Icon name="trash" size={15} color={C.danger}/>
            <Text style={[styles.ghostText, {"color": C.danger}]}>{"Tap again to delete" if confirm else "Delete"}</Text>
        </Pressable>
    </View>
}

def:pub TasksScreen(p: Planner, onOpen: Callable[[AssignmentView], None]) -> JsxElement {
    has draft: str = "",
        adding: bool = False;

    async def add -> None {
        if not draft.strip() or adding {
            return;
        }
        adding = True;
        ok = await p.quickAdd(draft);
        adding = False;
        if ok {
            draft = "";
        }
    }

    <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <View style={styles.row}>
            <TextInput
                style={styles.input}
                value={draft}
                placeholder="eecs482 p3 due fri 11:59pm #ag"
                placeholderTextColor={C.muted}
                autoCapitalize="none"
                onChangeText={lambda (t: str) { draft = t; }}
                onSubmitEditing={lambda { add(); }}
            />
            <Pressable style={[styles.button, {"paddingHorizontal": 14}]} disabled={adding} onPress={lambda { add(); }}>
                {(<ActivityIndicator color={C.white}/>) if adding else (<Icon name="plus" size={20} color={C.white}/>)}
            </Pressable>
        </View>
        <Text style={styles.small}>Tip: #gs Gradescope · #ag Autograder · ! or !! priority · "due tomorrow 5pm"</Text>
        <Seg
            options={[("open", "Open"), ("done", "Done"), ("all", "All")]}
            value={p.filterStatus}
            onPick={lambda (v: str) { p.setFilterStatus(v); }}
        />
        <ScrollView horizontal={True} showsHorizontalScrollIndicator={False} contentContainerStyle={{"gap": 6}}>
            <Pressable onPress={lambda { p.setFilterCourse(""); }} style={[styles.hoursChip, styles.hoursChipOn if not p.filterCourse else {}]}>
                <Text style={{"color": C.white if not p.filterCourse else C.text, "fontWeight": "600"}}>All</Text>
            </Pressable>
            {for c in p.courses {
                <Pressable key={c.id} onPress={lambda { p.setFilterCourse(c.id); }} style={[styles.hoursChip, {"backgroundColor": c.color, "borderColor": c.color} if p.filterCourse == c.id else {}]}>
                    <Text style={{"color": C.white if p.filterCourse == c.id else c.color, "fontWeight": "bold"}}>{c.code}</Text>
                </Pressable>
            }}
        </ScrollView>
        {(<View style={[styles.card, {"alignItems": "center"}]}>
            <Text style={{"fontSize": 26}}>🎉</Text>
            <Text style={styles.h2}>Nothing here</Text>
        </View>) if not p.assignments else <View/>}
        {for a in p.assignments {
            <TaskRow key={a.id} a={a} busy={p.busyId == a.id} onToggle={p.toggleDone} onOpen={onOpen}/>
        }}
    </ScrollView>
}
