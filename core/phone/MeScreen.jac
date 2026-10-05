"""Phone Me: account, Canvas sync, demo data, sign out."""

import from "@jac/mobui" { View, Text, ScrollView, Pressable, ActivityIndicator }
import from core.state { Planner }
import from .theme { C, styles }
import from .Icon { Icon }

def:pub MeScreen(p: Planner) -> JsxElement {
    can with entry {
        if p.settings is None {
            p.loadSettings();
        }
    }
    st = p.settings;
    connected = st is not None and (st.has_token or st.has_feed);

    <ScrollView contentContainerStyle={styles.scroll}>
        <View style={[styles.card, {"flexDirection": "row", "alignItems": "center", "gap": 12}]}>
            <View style={{"width": 44, "height": 44, "borderRadius": 22, "backgroundColor": C.maize, "alignItems": "center", "justifyContent": "center"}}>
                <Text style={{"color": C.maizeInk, "fontWeight": "bold", "fontSize": 18}}>{(p.session.username or "?")[0].upper()}</Text>
            </View>
            <View style={{"flex": 1}}>
                <Text style={styles.h2}>{p.session.username or "Signed in"}</Text>
                <Text style={styles.small}>Same account as the web app and CLI</Text>
            </View>
        </View>
        <View style={styles.card}>
            <Text style={styles.h2}>Canvas</Text>
            <Text style={styles.sub}>
                {("Connected " + (st.token_hint if st.has_token else "(calendar feed)") + (" · last sync " + st.last_sync.replace("T", " ") if st.last_sync else "")) if connected and st is not None else "Not connected - add your Canvas calendar feed in the web app's Settings."}
            </Text>
            {(<Pressable style={styles.button} disabled={p.syncBusy} onPress={lambda { p.syncCanvas(); }}>
                {(<ActivityIndicator color={C.white}/>) if p.syncBusy else (<Icon name="refresh" size={16} color={C.white}/>)}
                <Text style={styles.buttonText}>{"Syncing…" if p.syncBusy else "Sync now"}</Text>
            </Pressable>) if connected else <View/>}
        </View>
        <View style={styles.card}>
            <Text style={styles.h2}>AI assistant</Text>
            <Text style={styles.sub}>{("Using " + st.ai_model) if st is not None and st.ai_ready else "Built-in planner (no API key on the server)"}</Text>
        </View>
        {(<Pressable style={styles.maizeButton} onPress={lambda { p.loadDemo(); }}>
            <Text style={styles.maizeText}>Load demo semester</Text>
        </Pressable>) if not p.courses else <View/>}
        <Pressable style={styles.ghostButton} onPress={lambda { p.refresh(); }}>
            <Icon name="refresh" size={15} color={C.text}/>
            <Text style={styles.ghostText}>Refresh</Text>
        </Pressable>
        <Pressable style={styles.ghostButton} onPress={lambda { p.session.logout(); }}>
            <Icon name="logout" size={15} color={C.danger}/>
            <Text style={[styles.ghostText, {"color": C.danger}]}>Sign out</Text>
        </Pressable>
    </ScrollView>
}
