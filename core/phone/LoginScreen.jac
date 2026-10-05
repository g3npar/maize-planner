"""Phone sign-in: the same account as the web app and the CLI."""

import from "@jac/mobui" { View, Text, TextInput, Pressable, ActivityIndicator }
import from core.state { Session }
import from .theme { C, styles }

def:pub LoginScreen(session: Session) -> JsxElement {
    <View style={styles.loginWrap}>
        <View style={[styles.brandMark, {"width": 52, "height": 52, "borderRadius": 16}]}>
            <Text style={[styles.brandLetter, {"fontSize": 26}]}>M</Text>
        </View>
        <Text style={styles.loginTitle}>Maize Planner</Text>
        <Text style={styles.loginSub}>
            {"Create an account - it works on the web and in the CLI too." if session.signup else "Canvas, Gradescope and Autograder deadlines in your pocket."}
        </Text>
        <TextInput
            style={styles.loginInput}
            value={session.username}
            placeholder="Username"
            placeholderTextColor={C.muted}
            autoCapitalize="none"
            autoCorrect={False}
            onChangeText={lambda (t: str) { session.setUsername(t); }}
        />
        <TextInput
            style={styles.loginInput}
            value={session.password}
            placeholder="Password"
            placeholderTextColor={C.muted}
            secureTextEntry={True}
            onChangeText={lambda (t: str) { session.setPassword(t); }}
            onSubmitEditing={lambda { session.submit(); }}
        />
        {(<Text style={styles.error}>{session.error}</Text>) if session.error else <View/>}
        <Pressable style={styles.maizeButton} disabled={session.busy} onPress={lambda { session.submit(); }}>
            {(<ActivityIndicator color={C.maizeInk}/>) if session.busy else (<Text style={styles.maizeText}>{"Create account" if session.signup else "Sign in"}</Text>)}
        </Pressable>
        <Pressable onPress={lambda { session.toggleMode(); }}>
            <Text style={styles.link}>{"I already have an account" if session.signup else "New here? Create an account"}</Text>
        </Pressable>
    </View>
}
