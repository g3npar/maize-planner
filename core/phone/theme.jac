"""Design tokens and the StyleSheet for the phone app (React Native / mobUI)."""

import from "@jac/mobui" { StyleSheet }

obj Palette {
    has bg: str = "#f4f6fb",
        surface: str = "#ffffff",
        surface2: str = "#eef1f8",
        border: str = "#e1e6f0",
        text: str = "#0f172a",
        text2: str = "#334155",
        muted: str = "#64748b",
        primary: str = "#1d4ed8",
        navy: str = "#0f1f5c",
        maize: str = "#ffcb05",
        maizeInk: str = "#3b2f00",
        danger: str = "#dc2626",
        success: str = "#16a34a",
        white: str = "#ffffff";
}

obj Spacing {
    has xs: int = 4,
        sm: int = 8,
        md: int = 12,
        lg: int = 16,
        xl: int = 24;
}

obj Radius {
    has sm: int = 8,
        md: int = 12,
        lg: int = 18,
        pill: int = 999;
}

glob:pub C: Palette = Palette(),
     S: Spacing = Spacing(),
     R: Radius = Radius();

glob:pub styles = StyleSheet.create(
         {
             root: {flex: 1, backgroundColor: C.bg, width: "100%"},
             header: {
                 backgroundColor: C.navy,
                 paddingHorizontal: S.lg,
                 paddingBottom: S.md,
                 flexDirection: "row",
                 alignItems: "center",
                 gap: S.sm
             },
             brandMark: {
                 width: 30,
                 height: 30,
                 borderRadius: 9,
                 backgroundColor: C.primary,
                 alignItems: "center",
                 justifyContent: "center"
             },
             brandLetter: {color: C.maize, fontWeight: "bold", fontSize: 16},
             headerTitle: {color: C.white, fontSize: 18, fontWeight: "bold", flex: 1},
             headerButton: {padding: 6, borderRadius: R.pill},
             body: {flex: 1},
             scroll: {padding: S.lg, gap: S.md, paddingBottom: 40},
             h1: {color: C.text, fontSize: 24, fontWeight: "bold"},
             h2: {color: C.text, fontSize: 16, fontWeight: "bold"},
             sub: {color: C.muted, fontSize: 13},
             small: {color: C.muted, fontSize: 12},
             card: {
                 backgroundColor: C.surface,
                 borderRadius: R.lg,
                 borderWidth: 1,
                 borderColor: C.border,
                 padding: S.md,
                 gap: S.sm
             },
             row: {flexDirection: "row", alignItems: "center", gap: S.sm},
             between: {flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: S.sm},
             statRow: {flexDirection: "row", gap: S.sm},
             stat: {
                 flex: 1,
                 backgroundColor: C.surface,
                 borderRadius: R.md,
                 borderWidth: 1,
                 borderColor: C.border,
                 paddingVertical: S.sm,
                 alignItems: "center"
             },
             statValue: {fontSize: 20, fontWeight: "bold", color: C.text},
             statLabel: {fontSize: 11, color: C.muted},
             sectionTitle: {
                 color: C.muted,
                 fontSize: 12,
                 fontWeight: "bold",
                 marginTop: S.sm,
                 letterSpacing: 0.6
             },
             task: {
                 flexDirection: "row",
                 alignItems: "center",
                 gap: S.md,
                 backgroundColor: C.surface,
                 borderRadius: R.md,
                 borderWidth: 1,
                 borderColor: C.border,
                 paddingVertical: S.md,
                 paddingHorizontal: S.md
             },
             check: {
                 width: 24,
                 height: 24,
                 borderRadius: 12,
                 borderWidth: 2,
                 alignItems: "center",
                 justifyContent: "center"
             },
             taskTitle: {color: C.text, fontSize: 15, fontWeight: "600"},
             taskDone: {color: C.muted, fontSize: 15, textDecorationLine: "line-through"},
             chip: {
                 paddingHorizontal: 8,
                 paddingVertical: 2,
                 borderRadius: R.pill,
                 alignSelf: "flex-start"
             },
             chipText: {fontSize: 11, fontWeight: "bold"},
             due: {fontSize: 12, fontWeight: "600", color: C.text2, textAlign: "right"},
             dueIn: {fontSize: 11, fontWeight: "bold", textAlign: "right"},
             classBlock: {
                 borderLeftWidth: 4,
                 borderRadius: R.md,
                 backgroundColor: C.surface,
                 paddingVertical: S.sm,
                 paddingHorizontal: S.md,
                 gap: 2
             },
             input: {
                 flex: 1,
                 color: C.text,
                 fontSize: 15,
                 backgroundColor: C.surface,
                 borderWidth: 1,
                 borderColor: C.border,
                 borderRadius: R.md,
                 paddingVertical: 10,
                 paddingHorizontal: S.md
             },
             button: {
                 backgroundColor: C.primary,
                 borderRadius: R.md,
                 paddingVertical: 11,
                 paddingHorizontal: S.lg,
                 alignItems: "center",
                 justifyContent: "center",
                 flexDirection: "row",
                 gap: 6
             },
             buttonText: {color: C.white, fontWeight: "bold", fontSize: 15},
             ghostButton: {
                 borderRadius: R.md,
                 borderWidth: 1,
                 borderColor: C.border,
                 backgroundColor: C.surface,
                 paddingVertical: 9,
                 paddingHorizontal: S.md,
                 alignItems: "center",
                 flexDirection: "row",
                 gap: 6
             },
             ghostText: {color: C.text, fontWeight: "600", fontSize: 14},
             seg: {
                 flexDirection: "row",
                 backgroundColor: C.surface2,
                 borderRadius: R.md,
                 padding: 3,
                 gap: 3
             },
             segItem: {flex: 1, paddingVertical: 7, borderRadius: 9, alignItems: "center"},
             segOn: {backgroundColor: C.surface},
             segText: {color: C.muted, fontWeight: "600", fontSize: 13},
             segTextOn: {color: C.text, fontWeight: "bold", fontSize: 13},
             tabBar: {
                 flexDirection: "row",
                 borderTopWidth: 1,
                 borderTopColor: C.border,
                 backgroundColor: C.surface,
                 paddingTop: 6,
                 paddingBottom: 10
             },
             tabItem: {flex: 1, alignItems: "center", gap: 2},
             tabLabel: {fontSize: 11, color: C.muted},
             tabLabelOn: {fontSize: 11, color: C.primary, fontWeight: "bold"},
             banner: {
                 marginHorizontal: S.lg,
                 marginTop: S.sm,
                 padding: S.md,
                 borderRadius: R.md,
                 flexDirection: "row",
                 alignItems: "center",
                 gap: S.sm
             },
             bannerText: {flex: 1, color: C.white, fontSize: 13, fontWeight: "600"},
             sheet: {
                 backgroundColor: C.surface,
                 borderTopLeftRadius: 22,
                 borderTopRightRadius: 22,
                 padding: S.lg,
                 gap: S.md,
                 maxHeight: "88%"
             },
             sheetBackdrop: {flex: 1, backgroundColor: "rgba(8,12,28,0.45)", justifyContent: "flex-end"},
             step: {flexDirection: "row", alignItems: "center", gap: S.sm, paddingVertical: 6},
             box: {
                 width: 20,
                 height: 20,
                 borderRadius: 6,
                 borderWidth: 2,
                 borderColor: C.border,
                 alignItems: "center",
                 justifyContent: "center"
             },
             boxOn: {backgroundColor: C.success, borderColor: C.success},
             center: {flex: 1, alignItems: "center", justifyContent: "center", gap: S.md, padding: S.xl},
             loginWrap: {flex: 1, backgroundColor: C.navy, padding: S.xl, justifyContent: "center", gap: S.md},
             loginTitle: {color: C.white, fontSize: 28, fontWeight: "bold"},
             loginSub: {color: "#c7d2fe", fontSize: 14},
             loginInput: {
                 color: C.text,
                 fontSize: 16,
                 backgroundColor: C.white,
                 borderRadius: R.md,
                 paddingVertical: 12,
                 paddingHorizontal: S.md
             },
             maizeButton: {
                 backgroundColor: C.maize,
                 borderRadius: R.md,
                 paddingVertical: 13,
                 alignItems: "center"
             },
             maizeText: {color: C.maizeInk, fontWeight: "bold", fontSize: 16},
             link: {color: "#c7d2fe", fontSize: 14, textAlign: "center"},
             error: {color: "#fecaca", fontSize: 13, fontWeight: "600"},
             planBlock: {
                 borderLeftWidth: 4,
                 borderRadius: R.md,
                 backgroundColor: C.surface,
                 padding: S.md,
                 gap: 3
             },
             hoursChip: {
                 paddingHorizontal: 14,
                 paddingVertical: 8,
                 borderRadius: R.pill,
                 borderWidth: 1,
                 borderColor: C.border,
                 backgroundColor: C.surface
             },
             hoursChipOn: {backgroundColor: C.primary, borderColor: C.primary}
         }
     );
