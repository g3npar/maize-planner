"""Phone Classes: schedule, grade, and one-tap links to every platform."""

import from "@jac/mobui" { View, Text, ScrollView, Pressable, Linking }
import from core.planner { CourseView }
import from core.state { Planner, fmt_pct }
import from .theme { C, styles }
import from .Icon { Icon }

def:pub LinkButton(label: str, url: str, color: str) -> JsxElement {
    if not url {
        return <View/>;
    }
    <Pressable style={styles.ghostButton} onPress={lambda { Linking.openURL(url); }}>
        <Icon name="open" size={13} color={color}/>
        <Text style={[styles.ghostText, {"color": color, "fontSize": 13}]}>{label}</Text>
    </Pressable>
}

def:pub CourseCard(c: CourseView) -> JsxElement {
    g = c.grade;
    <View style={[styles.card, {"borderTopWidth": 5, "borderTopColor": c.color}]}>
        <View style={styles.between}>
            <View style={{"flex": 1}}>
                <Text style={[styles.h1, {"fontSize": 20}]}>{c.code}</Text>
                <Text style={styles.sub} numberOfLines={1}>{c.name or c.term}</Text>
            </View>
            <View style={{"alignItems": "flex-end"}}>
                <Text style={[styles.h1, {"fontSize": 20, "color": c.color}]}>{g.letter or "–"}</Text>
                <Text style={styles.small}>{fmt_pct(g.current)}</Text>
            </View>
        </View>
        <Text style={styles.small}>
            {str(c.open_count) + " open" + (" · " + str(c.overdue_count) + " overdue" if c.overdue_count else "") + (" · next " + c.next_due if c.next_due else "")}
        </Text>
        {for m in c.meetings {
            <View key={m.id} style={styles.row}>
                <Icon name="clock" size={12} color={C.muted}/>
                <Text style={[styles.small, {"color": C.text2}]}>{m.kind + " · " + m.days_label + " " + m.time_label + (" · " + m.location if m.location else "")}</Text>
            </View>
        }}
        {(<Text style={[styles.small, {"color": C.primary}]}>{g.note}</Text>) if g.note and g.current is not None else <View/>}
        <View style={[styles.row, {"flexWrap": "wrap"}]}>
            <LinkButton label="Canvas" url={c.canvas_url} color="#e2432b"/>
            <LinkButton label="Gradescope" url={c.gradescope_url} color="#1a8a88"/>
            <LinkButton label="Autograder" url={c.autograder_url} color="#7c3aed"/>
            <LinkButton label="Website" url={c.website_url} color={C.text2}/>
        </View>
    </View>
}

def:pub ClassesScreen(p: Planner) -> JsxElement {
    <ScrollView contentContainerStyle={styles.scroll}>
        {(<View style={[styles.card, {"alignItems": "center"}]}>
            <Text style={{"fontSize": 26}}>📚</Text>
            <Text style={styles.h2}>No classes yet</Text>
            <Text style={styles.sub}>Add them on the web app, or sync from Canvas.</Text>
        </View>) if not p.courses else <View/>}
        {for c in p.courses {
            <CourseCard key={c.id} c={c}/>
        }}
    </ScrollView>
}
