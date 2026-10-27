import AppKit
import BirdingCore

extension DesktopController {
    @objc func showSceneEditor() {
        if let sceneEditor,sceneEditor.window?.isVisible == true {sceneEditor.window?.makeKeyAndOrderFront(nil);return}
        syncWorld();sceneEditor=SceneEditorWindow(desktop:self);sceneEditor?.showWindow(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    func loadSceneLayout() {
        let store=ScenePersistence(url:settingsURL.deletingLastPathComponent().appendingPathComponent("scene-layout.json"))
        scenePersistence=store
        engine.sceneWriter={try store.save($0)}
        do {try engine.restoreScene(store.load(legacyAnchors:settings.fixedPerches));sceneLayoutLoaded=true}
        catch {NSLog("ChirpOS scene: %@",error.localizedDescription)}
    }
    @objc func chooseCompanionMode(_ sender:NSMenuItem) {
        guard CompanionMode.allCases.indices.contains(sender.tag) else {return}
        var updated=settings;var preferences=updated.companion ?? CompanionPreferences.migrate(updated)
        preferences.mode=CompanionMode.allCases[sender.tag];updated.companion=preferences
        do {try applySettings(updated);settingsWindow?.externalCompanionChanged(preferences);makeMenu()}
        catch {let alert=NSAlert();alert.messageText="模式保存失败";alert.informativeText=error.localizedDescription;alert.runModal()}
    }
    func addCompanionMenu(to menu:NSMenu) {
        let item=NSMenuItem(title:t("陪伴模式","Companion mode"),action:nil,keyEquivalent:"")
        let modes=NSMenu();item.submenu=modes
        for (index,title) in [t("专注 · 更少活动","Focus · Less activity"),t("自然 · 均衡陪伴","Natural · Balanced"),t("活泼 · 完整动作","Lively · Full performances")].enumerated() {
            let mode=NSMenuItem(title:title,action:#selector(chooseCompanionMode(_:)),keyEquivalent:"")
            mode.target=self;mode.tag=index;mode.state=settings.companion?.mode==CompanionMode.allCases[index] ? .on:.off;modes.addItem(mode)
        }
        menu.addItem(item);add(menu,t("布置桌面…","Arrange desktop…"),#selector(showSceneEditor),"e")
    }
}
extension SpeciesSettingsWindow {
    func buildCompanionSettings()->NSView {
        let view=SettingsContentView(frame:NSRect(x:0,y:0,width:754,height:930))
        if draft.companion==nil {draft.companion=CompanionPreferences.migrate(draft)}
        let prefs=draft.companion!
        label(t("陪伴模式","Companion mode"),NSRect(x:20,y:18,width:700,height:30),in:view,size:22)
        companionModePopup=NSPopUpButton(frame:NSRect(x:20,y:60,width:360,height:32),pullsDown:false)
        companionModePopup.addItems(withTitles:[t("专注 · 更少活动","Focus · Less activity"),t("自然 · 均衡陪伴","Natural · Balanced"),t("活泼 · 完整动作","Lively · Full performances")])
        companionModePopup.selectItem(at:CompanionMode.allCases.firstIndex(of:prefs.mode)!)
        companionModePopup.target=self;companionModePopup.action=#selector(companionChanged);view.addSubview(companionModePopup)
        label(t("普通飞行减少绕路；鸟群拥有独立计划。保存后生效。","Direct ordinary flights and independently scheduled flocks. Save to apply."),NSRect(x:20,y:104,width:710,height:40),in:view)
        flockPassesButton.removeFromSuperview();flockPassesButton.frame=NSRect(x:20,y:152,width:700,height:26);view.addSubview(flockPassesButton)
        companionDayNight=NSButton(checkboxWithTitle:t("跟随本地昼夜","Follow local day/night"),target:self,action:#selector(companionChanged))
        companionDayNight.state=prefs.followLocalDayNight ? .on:.off;companionDayNight.frame=NSRect(x:20,y:190,width:600,height:26);view.addSubview(companionDayNight)
        companionManual=NSButton(checkboxWithTitle:t("手动调整行为","Customize behaviors"),target:self,action:#selector(companionChanged))
        companionManual.state=prefs.manualAdjustmentEnabled ? .on:.off;companionManual.frame=NSRect(x:20,y:230,width:600,height:26);view.addSubview(companionManual)
        _=button(t("恢复模式默认","Restore mode defaults"),#selector(restoreCompanionDefaults),NSRect(x:20,y:275,width:200,height:32),in:view)
        label(t("清除类别覆盖与旧版行为例外；鸟群、赠礼等独立开关保持当前值。","Clears category overrides and legacy exceptions; independent flock and gift switches keep their values."),NSRect(x:235,y:273,width:480,height:50),in:view,size:12)
        let scene=button(t("布置桌面…","Arrange desktop…"),#selector(openSceneEditor),NSRect(x:20,y:334,width:200,height:32),in:view)
        scene.toolTip=t("拖拽布置栖木、食盘、浴盆、巢台和叶片。布局与资源独立保存。","Drag perches, trays, baths, nests and leaves. Layout and resources are saved independently.")
        let advanced=button(t("单项开关与行为体验…","Individual switches and previews…"),#selector(selectPage(_:)),NSRect(x:235,y:334,width:330,height:32),in:view);advanced.tag=4
        companionCategoryControls=[]
        for (index,category) in BehaviorCategory.allCases.enumerated() {
            let names=[t("飞行与绕飞","Flight"),t("停栖小动作","Perch actions"),t("双鸟社交","Social"),t("场景互动","Scenes")]
            let y=CGFloat(400+index*70),override=prefs.categoryOverrides[category] ?? BehaviorCategoryOverride()
            let enabled=NSButton(checkboxWithTitle:names[index],target:self,action:#selector(companionChanged));enabled.state=override.enabled ? .on:.off
            enabled.frame=NSRect(x:20,y:y,width:210,height:28)
            let frequency=NSPopUpButton(frame:NSRect(x:250,y:y,width:190,height:30),pullsDown:false)
            frequency.addItems(withTitles:[t("频率跟随模式","Preset frequency"),t("较少","Less"),t("适中","Medium"),t("较多","More")])
            frequency.selectItem(at:override.frequency.flatMap{AmbientFrequency.allCases.firstIndex(of:$0)}.map{$0+1} ?? 0)
            let duration=NSPopUpButton(frame:NSRect(x:460,y:y,width:230,height:30),pullsDown:false)
            duration.addItems(withTitles:[t("长度跟随模式","Preset duration"),t("简短","Short"),t("适中","Balanced"),t("完整","Full")])
            duration.selectItem(at:override.duration.flatMap{DurationStyle.allCases.firstIndex(of:$0)}.map{$0+1} ?? 0)
            for control in [frequency,duration] {control.target=self;control.action=#selector(companionChanged)}
            for control in [enabled,frequency,duration] as [NSControl] {control.isEnabled=prefs.manualAdjustmentEnabled;control.isHidden = !prefs.manualAdjustmentEnabled;view.addSubview(control)}
            companionCategoryControls.append((enabled,frequency,duration))
        }
        let restrictions=prefs.automaticRestrictions.map(\.rawValue).sorted().joined(separator:", ")
        companionExceptions=label(restrictions.isEmpty ? t("旧版单项关闭偏好在「单项开关」中保留。","Legacy explicit switches remain under Individual switches."):
            t("保留的旧版自动行为限制：","Preserved legacy automatic restrictions: ")+restrictions,NSRect(x:20,y:700,width:710,height:90),in:view,size:12)
        _=button(t("清除旧版自动限制","Clear legacy automatic restrictions"),#selector(clearAutomaticRestrictions),NSRect(x:20,y:800,width:300,height:32),in:view)
        return scroll(view)
    }
    @objc func companionChanged() {
        guard companionModePopup != nil else {return}
        var p=draft.companion ?? CompanionPreferences()
        p.mode=CompanionMode.allCases[companionModePopup.indexOfSelectedItem]
        p.followLocalDayNight=companionDayNight.state == .on;p.manualAdjustmentEnabled=companionManual.state == .on
        for (i,controls) in companionCategoryControls.enumerated() {
            var value=BehaviorCategoryOverride();value.enabled=controls.0.state == .on
            value.frequency=controls.1.indexOfSelectedItem==0 ? nil:AmbientFrequency.allCases[controls.1.indexOfSelectedItem-1]
            value.duration=controls.2.indexOfSelectedItem==0 ? nil:DurationStyle.allCases[controls.2.indexOfSelectedItem-1]
            p.categoryOverrides[BehaviorCategory.allCases[i]]=value
            for control in [controls.0,controls.1,controls.2] as [NSControl] {control.isEnabled=p.manualAdjustmentEnabled;control.isHidden = !p.manualAdjustmentEnabled}
        }
        draft.companion=p;companionConflict=false;message?.stringValue=t("尚未保存","Unsaved changes")
    }
    func externalCompanionChanged(_ incoming:CompanionPreferences) {
        if draft.companion?.mode==companionBaseline?.mode {
            draft.companion?.mode=incoming.mode;companionModePopup?.selectItem(at:CompanionMode.allCases.firstIndex(of:incoming.mode)!)
        } else if draft.companion?.mode != incoming.mode {
            companionConflict=true;message?.stringValue=t("菜单已切换模式。请重新选择要保存的模式，确认后再保存。","Mode changed from the menu. Select the mode you want again before saving.")
        }
        companionBaseline=incoming
    }
    @objc func restoreCompanionDefaults() {draft.companion?.restoreModeDefaults();build();message.stringValue=t("已恢复模式默认，保存后生效。","Mode defaults restored; save to apply.")}
    @objc func clearAutomaticRestrictions() {draft.companion?.automaticRestrictions=[];build();message.stringValue=t("已清除旧版自动限制，保存后生效。","Legacy automatic restrictions cleared; save to apply.")}
    @objc func openSceneEditor() {desktop.showSceneEditor()}
}
