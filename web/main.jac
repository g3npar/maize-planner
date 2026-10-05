"""Web app entry: the browser UI for the planner.

The planner service (core/planner.jac, [apps.planner]) is colocated in this
process by `jac run`; every screen reaches it through core/state.jac.
"""

import from .PlannerWeb { PlannerWeb }
import "./styles.css";

def:pub app -> JsxElement {
    <PlannerWeb/>
}
