"""The phone app. Rendered natively by mobile/main.jac (Expo / React Native)
and inside the web app's "Phone app" page through react-native-web.

It is a thin mobUI view over `usePlanner()` (core/state.jac) - the exact
same state and actions the web app uses - so both UIs stay in lockstep.
"""

import from "@jac/mobui" { View, Text, Pressable, StatusBar, ActivityIndicator, useWindowDimensions }
import from core.planner { AssignmentView }
import from core.state { usePlanner }
import from .theme { C, styles }
import from .Icon { Icon }
import from .parts { TabBar, Banner }
import from .LoginScreen { LoginScreen }
import from .TodayScreen { TodayScreen }
import from .TasksScreen { TasksScreen, TaskSheet }
import from .ClassesScreen { ClassesScreen }
import from .PlanScreen { PlanScreen }
import from .MeScreen { MeScreen }

glob PHONE_TITLES: dict[str, str] = {
         "today": "Today",
         "tasks": "Tasks",
         "classes": "Classes",
         "plan": "Study plan",
         "me": "Me"
     };

def:pub PlannerPhone(embedded: bool = False) -> JsxElement {
    p = usePlanner();
    viewport = useWindowDimensions();
    has tab: str = "today",
        openId: str = "";

    open_item = p.findAssignment(openId) if openId else None;
    rootStyle = [styles.root, {"height": "100%" if embedded else viewport.height, "paddingTop": 0}];

    def open(a: AssignmentView) {
        openId = a.id;
    }

    if p.session.checking {
        return <View style={[styles.root, styles.center]}><ActivityIndicator color={C.primary}/></View>;
    }
    if not p.session.loggedIn {
        return <View style={rootStyle}><LoginScreen session={p.session}/></View>;
    }

    overdue = p.dashboard.stats.overdue if p.dashboard is not None else 0;

    <View style={rootStyle}>
        <StatusBar barStyle="light-content" backgroundColor={C.navy}/>
        <View style={[styles.header, {"paddingTop": 44 if embedded else 48}]}>
            <View style={styles.brandMark}><Text style={styles.brandLetter}>M</Text></View>
            <Text style={styles.headerTitle}>{PHONE_TITLES[tab] if tab in PHONE_TITLES else "Planner"}</Text>
            <Pressable accessibilityLabel="Refresh" style={styles.headerButton} onPress={lambda { p.refresh(); }}>
                {(<ActivityIndicator size="small" color={C.maize}/>) if p.refreshing else (<Icon name="refresh" size={18} color={C.maize}/>)}
            </Pressable>
        </View>
        {(<Banner message={p.error} color={C.danger} onClose={p.dismiss}/>) if p.error else <View/>}
        {(<Banner message={p.notice} color={C.success} onClose={p.dismiss}/>) if p.notice and not p.error else <View/>}
        <View style={styles.body}>
            {if tab == "today" {
                <TodayScreen p={p} onOpen={open} go={lambda (t: str) { tab = t; }}/>
            } elif tab == "tasks" {
                <TasksScreen p={p} onOpen={open}/>
            } elif tab == "classes" {
                <ClassesScreen p={p}/>
            } elif tab == "plan" {
                <PlanScreen p={p}/>
            } else {
                <MeScreen p={p}/>
            }}
        </View>
        <TabBar active={tab} onPick={lambda (t: str) { tab = t; }} overdue={overdue}/>
        {(<View style={[styles.sheetBackdrop, {"position": "absolute", "top": 0, "left": 0, "right": 0, "bottom": 0}]}>
            <Pressable style={{"flex": 1}} onPress={lambda { openId = ""; }}/>
            <TaskSheet key={open_item.id} p={p} a={open_item} onClose={lambda { openId = ""; }}/>
        </View>) if open_item is not None else <View/>}
    </View>
}
