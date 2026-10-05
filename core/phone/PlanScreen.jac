"""Phone Plan: pick how long you have, get a laid-out study session."""

import from "@jac/mobui" { View, Text, ScrollView, Pressable, ActivityIndicator }
import from core.planner { StudyPlan }
import from core.state { Planner }
import from .theme { C, styles }
import from .Icon { Icon }

def short_clock(iso: str) -> str {
    if len(iso) < 16 {
        return iso;
    }
    h = int(iso[11:13]);
    h12 = h % 12;
    if h12 == 0 {
        h12 = 12;
    }
    return str(h12) + ":" + iso[14:16] + (" AM" if h < 12 else " PM");
}

def:pub PlanBlocks(plan: StudyPlan) -> JsxElement {
    <View style={{"gap": 10}}>
        <View style={styles.card}>
            <Text style={[styles.small, {"fontWeight": "bold", "color": "#7c3aed" if plan.source == "ai" else C.muted}]}>{"AI PLAN" if plan.source == "ai" else "BUILT-IN PLANNER"}</Text>
            <Text style={[styles.h2, {"fontWeight": "600"}]}>{plan.summary}</Text>
        </View>
        {for b in plan.blocks {
            <View key={b.start + b.assignment_id} style={[styles.planBlock, {"borderLeftColor": b.color}]}>
                <Text style={[styles.small, {"fontWeight": "bold", "color": C.text2}]}>{short_clock(b.start) + " – " + short_clock(b.end) + "  ·  " + str(b.minutes) + " min"}</Text>
                <Text style={styles.h2}>{b.course_code + " · " + b.title}</Text>
                <Text style={styles.small}>{b.reason}</Text>
            </View>
        }}
        {for t in plan.tips {
            <Text key={t} style={styles.sub}>{"💡 " + t}</Text>
        }}
    </View>
}

def:pub PlanScreen(p: Planner) -> JsxElement {
    has hours: float = 2.0;
    plan = p.plan;

    <ScrollView contentContainerStyle={styles.scroll}>
        <Text style={styles.h1}>Study session</Text>
        <Text style={styles.sub}>How much time do you have?</Text>
        <View style={[styles.row, {"flexWrap": "wrap"}]}>
            {for h in [1.0, 2.0, 3.0, 4.0, 6.0] {
                <Pressable key={str(h)} style={[styles.hoursChip, styles.hoursChipOn if hours == h else {}]} onPress={lambda { hours = h; }}>
                    <Text style={{"color": C.white if hours == h else C.text, "fontWeight": "bold"}}>{f"{h:g}h"}</Text>
                </Pressable>
            }}
        </View>
        <Pressable style={styles.button} disabled={p.planBusy} onPress={lambda { p.makePlan(hours, "", True); }}>
            {(<ActivityIndicator color={C.white}/>) if p.planBusy else (<Icon name="magic" size={16} color={C.white}/>)}
            <Text style={styles.buttonText}>{"Planning…" if p.planBusy else "Build my plan"}</Text>
        </Pressable>
        {(<PlanBlocks plan={plan}/>) if plan is not None else <View/>}
    </ScrollView>
}
