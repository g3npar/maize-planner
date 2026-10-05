"""The phone app, live inside the website.

`PlannerPhone` is the exact component `mobile/main.jac` ships to Android and
iOS. Here react-native-web renders it inside a device frame, signed in with
the same session, so the phone UI can be tried without a device.
"""

import from "lucide-react" { Smartphone, QrCode, Package, Globe }
import from core.phone.PlannerPhone { PlannerPhone }

def:pub PhonePage -> JsxElement {
    <div className="phone-wrap">
        <div>
            <div className="phone">
                <div className="phone-screen">
                    <PlannerPhone embedded={True}/>
                </div>
            </div>
            <p className="muted small" style={{"textAlign": "center", "marginTop": "12px"}}>Live - tap around. It shares your account and data with this page.</p>
        </div>
        <div className="stack" style={{"gap": "20px", "maxWidth": "560px"}}>
            <div className="card">
                <div className="card-head"><Smartphone size={17}/><h2>This is the real mobile app</h2></div>
                <div className="stack small">
                    <div>The phone UI in <code>core/phone/</code> is written with <b>mobUI</b> (React Native primitives - no HTML). The <code>mobile</code> app in <code>jac.toml</code> builds it for Android and iOS through Expo; this page renders the very same component with react-native-web.</div>
                    <div>Both it and the web app use one state hook, <code>core/state.jac</code>, which calls the walkers of the <code>planner</code> service. Check something off on the phone and the web list updates.</div>
                </div>
            </div>
            <div className="card">
                <div className="card-head"><QrCode size={17}/><h2>Run it on your phone (Expo Go)</h2></div>
                <div className="stack small">
                    <div>With the server running (<code>jac run</code>), in a second terminal:</div>
                    <code className="cmd">{"jac setup mobile        # first time only" + chr(10) + "jac run --dev mobile    # starts Metro and prints a QR code"}</code>
                    <div>Scan the QR code with the Expo Go app (phone on the same Wi-Fi). The phone talks to the same planner server over your LAN.</div>
                </div>
            </div>
            <div className="card">
                <div className="card-head"><Package size={17}/><h2>Build an installable app</h2></div>
                <div className="stack small">
                    <code className="cmd">{"jac build mobile --platform android   # APK" + chr(10) + "jac build mobile --platform ios       # macOS + Xcode"}</code>
                </div>
            </div>
        </div>
    </div>
}
