"""Phone Today: next class, today's classes, and everything due soon."""

import from "@jac/mobui" { View, Text, ScrollView, Pressable }
import from core.planner { AssignmentView, ClassSlot }
import from core.state { Planner }
import from .theme { C, styles }
import from .parts { TaskRow, SectionHeader }
import from .Icon { Icon }

def:pub ClassCard(s: ClassSlot, label: str = "") -> JsxElement {
    <View style={[styles.classBlock, {"borderLeftColor": s.color, "opacity": 0.55 if s.state == "past" else 1}]}>
        <View style={styles.between}>
            <Text style={styles.h2}>{s.course_code + " · " + s.kind}</Text>
            {(<Text style={[styles.small, {"color": s.color, "fontWeight": "bold"}]}>{label}</Text>) if label else <View/>}
        </View>
        <View style={styles.row}>
            <Icon name="clock" size={12} color={C.muted}/>
            <Text style={styles.small}>{s.time_label}</Text>
            {(<Icon name="pin" size={12} color={C.muted}/>) if s.location else <View/>}
            <Text style={styles.small}>{s.location}</Text>
        </View>
    </View>
}

def:pub DueGroup(
    title: str,
    color: str,
    items: list[AssignmentView],
    p: Planner,
    onOpen: Callable[[AssignmentView], None]
) -> JsxElement {
    shown = p.visible(items);
    if not shown {
        return <View/>;
    }
    <View style={{"gap": 8}}>
        <SectionHeader title={title} count={len(shown)} color={color}/>
        {for a in shown {
            <TaskRow key={a.id} a={a} busy={p.busyId == a.id} onToggle={p.toggleDone} onOpen={onOpen}/>
        }}
    </View>
}

def:pub TodayScreen(p: Planner, onOpen: Callable[[AssignmentView], None], go: Callable[[str], None]) -> JsxElement {
    d = p.dashboard;
    if d is None {
        return <View style={styles.center}><Text style={styles.sub}>Loading…</Text></View>;
    }
    s = d.stats;
    nothing = not d.overdue and not d.today and not d.tomorrow and not d.week;
    upcoming = [c for c in d.classes_today if c.state != "past"];

    <ScrollView contentContainerStyle={styles.scroll}>
        <View style={{"gap": 2}}>
            <Text style={styles.h1}>{d.greeting}</Text>
            <Text style={styles.sub}>{d.date_label}</Text>
        </View>
        <View style={styles.statRow}>
            <View style={styles.stat}>
                <Text style={[styles.statValue, {"color": C.danger if s.overdue > 0 else C.text}]}>{str(s.overdue)}</Text>
                <Text style={styles.statLabel}>overdue</Text>
            </View>
            <View style={styles.stat}>
                <Text style={styles.statValue}>{str(s.due_today)}</Text>
                <Text style={styles.statLabel}>due today</Text>
            </View>
            <View style={styles.stat}>
                <Text style={styles.statValue}>{str(s.due_week)}</Text>
                <Text style={styles.statLabel}>this week</Text>
            </View>
            <View style={styles.stat}>
                <Text style={styles.statValue}>{str(s.done_week)}</Text>
                <Text style={styles.statLabel}>done</Text>
            </View>
        </View>
        {(<View style={styles.card}>
            <Text style={styles.h2}>Welcome! Nothing here yet.</Text>
            <Text style={styles.sub}>Connect Canvas from the web app's Settings, or load a demo semester to explore.</Text>
            <Pressable style={styles.maizeButton} onPress={lambda { p.loadDemo(); }}>
                <Text style={styles.maizeText}>Load demo semester</Text>
            </Pressable>
        </View>) if d.course_count == 0 else <View/>}
        {(<View style={{"gap": 8}}>
            <Text style={styles.sectionTitle}>{"CLASSES TODAY" if len(d.classes_today) > 0 else "NEXT CLASS"}</Text>
            {for c in (upcoming if len(upcoming) > 0 else d.classes_today) {
                <ClassCard key={c.course_id + c.start} s={c} label={"NOW" if c.state == "now" else ""}/>
            }}
            {(<ClassCard s={d.next_class} label={d.next_class.state}/>) if d.next_class is not None and not d.classes_today else <View/>}
        </View>) if len(d.classes_today) > 0 or d.next_class is not None else <View/>}
        {(<View style={[styles.card, {"alignItems": "center"}]}>
            <Text style={{"fontSize": 28}}>🎉</Text>
            <Text style={styles.h2}>Nothing due this week</Text>
            <Text style={styles.sub}>Add something from the Tasks tab.</Text>
        </View>) if nothing and d.course_count > 0 else <View/>}
        <DueGroup title="Overdue" color={C.danger} items={d.overdue} p={p} onOpen={onOpen}/>
        <DueGroup title="Today" color="#ea580c" items={d.today} p={p} onOpen={onOpen}/>
        <DueGroup title="Tomorrow" color="#ca8a04" items={d.tomorrow} p={p} onOpen={onOpen}/>
        <DueGroup title="This week" color={C.primary} items={d.week} p={p} onOpen={onOpen}/>
        <Pressable style={styles.ghostButton} onPress={lambda { go("plan"); }}>
            <Icon name="plan" size={16} color={C.primary}/>
            <Text style={styles.ghostText}>Plan my next study session</Text>
        </Pressable>
    </ScrollView>
}
