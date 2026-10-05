"""Mobile app entry (Expo / React Native via mobUI).

The UI lives in core/phone/ so the web app can embed the very same component
in its "Phone app" page. Every screen talks to the planner service through
core/state.jac; there is no backend in the phone.
"""

import from core.phone.PlannerPhone { PlannerPhone }

def:pub app -> JsxElement {
    return <PlannerPhone/>;
}
