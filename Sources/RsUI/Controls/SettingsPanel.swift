import UWP
import WinUI
import WindowsFoundation

open class SettingsPanel: WinUI.Grid, @unchecked Sendable {
    public var isMainShown: Bool = true

    /// append 登记的 group 信息：头部快捷跳转按钮、当前可见性（setGroup 的目标值）
    /// 与收起时钉住的原始高度（重显时的展开目标）。key 用 ObjectIdentifier——
    /// 调用方持有的 SettingsGroup Swift 实例是唯一身份来源。
    private struct GroupRegistration {
        let button: AppBarButton?
        var isVisible: Bool
        var pinnedHeight: Double?
    }
    private var groupRegistrations: [ObjectIdentifier: GroupRegistration] = [:]

    private let ui:
        (
            root: Grid,
            backButton: Button,
            headerPanel: StackPanel,
            secondHeaderPanel: StackPanel,

            mainScrollView: ScrollView,
            mainPanel: StackPanel,
            secondPanel: Grid,

            mainShownStoryboard: Storyboard,
            mainHiddenStoryboard: Storyboard,
            secondShownStoryboard: Storyboard,
            secondHiddenStoryboard: Storyboard,
        )

    public nonisolated override init() {
        typealias UI = (
            root: Grid, backButton: Button, headerPanel: StackPanel, secondHeaderPanel: StackPanel,
            mainScrollView: ScrollView, mainPanel: StackPanel, secondPanel: Grid,
            mainShownStoryboard: Storyboard, mainHiddenStoryboard: Storyboard,
            secondShownStoryboard: Storyboard, secondHiddenStoryboard: Storyboard
        )
        let built = MainActor.assumeIsolated { () -> UI in
            let loaded: Grid = App.context.requireXaml(withString: xamlUI)
            return (
                root: loaded,
                backButton: loaded.requireElement("BackButton"),
                headerPanel: loaded.requireElement("HeaderPanel"),
                secondHeaderPanel: loaded.requireElement("SecondHeaderPanel"),

                mainScrollView: loaded.requireElement("MainScrollView"),
                mainPanel: loaded.requireElement("MainPanel"),
                secondPanel: loaded.requireElement("SecondPanel"),

                mainShownStoryboard: loaded.requireResource("MainShownStoryboard"),
                mainHiddenStoryboard: loaded.requireResource("MainHiddenStoryboard"),
                secondShownStoryboard: loaded.requireResource("SecondShownStoryboard"),
                secondHiddenStoryboard: loaded.requireResource("SecondHiddenStoryboard")
            )
        }
        ui = built

        super.init()
        MainActor.assumeIsolated {
            children.append(ui.root)

            ui.backButton.click.addHandler { [weak self] _, _ in
                guard let self else { return }
                self.isMainShown = true

                ui.backButton.visibility = .collapsed
                ui.headerPanel.visibility = .visible
                ui.secondHeaderPanel.visibility = .collapsed
                ui.mainPanel.visibility = .visible
                ui.secondPanel.visibility = .collapsed

                ui.secondHeaderPanel.children.clear()
                ui.secondPanel.children.clear()

                try? ui.mainShownStoryboard.begin()
                try? ui.secondHiddenStoryboard.begin()
            }
        }
    }

    public func append(glyph: String?, group: SettingsGroup) {
        ui.mainPanel.children.append(group)

        var button: AppBarButton?
        if let glyph {
            let jumpButton = AppBarButton.makeIconOnly(glyph: glyph, tooltip: group.title)
            jumpButton.click.addHandler { [weak self] _, _ in
                guard
                    let self,
                    let transform = try? group.transformToVisual(ui.mainScrollView),
                    let point = try? transform.transformPoint(.init(x: 0, y: 0))
                else { return }

                let offset = min(ui.mainScrollView.scrollableHeight, max(0.0, ui.mainScrollView.verticalOffset + Double(point.y)))
                _ = try? ui.mainScrollView.scrollTo(0, offset)
            }
            ui.headerPanel.children.append(jumpButton)
            button = jumpButton
        }
        groupRegistrations[ObjectIdentifier(group)] = GroupRegistration(button: button, isVisible: true)
    }

    @discardableResult
    public func append(glyph: String?, title: String, cards: [UIElement]) -> SettingsGroup {
        let group = SettingsGroup(title: title, cards: cards)
        append(glyph: glyph, group: group)
        return group
    }

    /// 显示或隐藏一个已 append 的 group（连同其头部快捷跳转按钮）。
    /// 高度展开/收起（节奏对齐 SettingsGroup 卡片宿主：0.333s EaseOut / 0.133s EaseIn），
    /// 面板内后续 group 随布局上下滑动；头部按钮直接切换可见性（横向栈内邻居位移
    /// 无法平滑，半程动画反而显脏）。同值重复设置为 no-op，未 append 的 group 静默忽略。
    public func setGroup(_ group: SettingsGroup, visible: Bool) {
        let key = ObjectIdentifier(group)
        guard var registration = groupRegistrations[key], registration.isVisible != visible else { return }

        registration.isVisible = visible
        registration.button?.visibility = visible ? .visible : .collapsed

        let storyboard = Storyboard()
        let easing = CubicEase()

        if visible {
            // 从未隐藏过（初始即显示）时无钉住高度，直接显示即可
            guard let height = registration.pinnedHeight else {
                groupRegistrations[key] = registration
                group.visibility = .visible
                return
            }
            groupRegistrations[key] = registration

            group.visibility = .visible
            easing.easingMode = .easeOut
            let duration = makeDuration(milliseconds: 333)
            addAnimation(to: storyboard, target: group, property: "Height", to: height, duration: duration, easing: easing, enablesDependentAnimation: true)
            addAnimation(to: storyboard, target: group, property: "Opacity", to: 1.0, duration: duration, easing: easing)
            storyboard.completed.addHandler { [weak self, weak group] _, _ in
                guard let self, let group else { return }
                // 展开完成交还自然布局并清掉钉住高度（组内状态可能已变化）；
                // 期间目标又翻转为隐藏则保持钉住，由收起动画从当前高度接管
                if groupRegistrations[ObjectIdentifier(group)]?.isVisible == true {
                    group.height = Double.nan
                    groupRegistrations[ObjectIdentifier(group)]?.pinnedHeight = nil
                }
            }
        } else {
            // 展开半途反向收起时不重抓高度，保留原钉住值作为重显目标
            if registration.pinnedHeight == nil {
                registration.pinnedHeight = group.actualHeight
            }
            groupRegistrations[key] = registration

            group.height = group.actualHeight
            easing.easingMode = .easeIn
            let duration = makeDuration(milliseconds: 133)
            addAnimation(to: storyboard, target: group, property: "Height", to: 0.0, duration: duration, easing: easing, enablesDependentAnimation: true)
            addAnimation(to: storyboard, target: group, property: "Opacity", to: 0.0, duration: duration, easing: easing)
            storyboard.completed.addHandler { [weak self, weak group] _, _ in
                guard let self, let group else { return }
                // completed 晚于目标值翻转（收起中被重新显示）时不折叠。
                // 折叠移除相邻 16px 间距的定格跳变无法避免（StackPanel spacing
                // 不可动画），方向与滑动一致故不显突兀
                if groupRegistrations[ObjectIdentifier(group)]?.isVisible == false {
                    group.visibility = .collapsed
                }
            }
        }

        try? storyboard.begin()
    }

    /// From 一律省略：以当前值为起点，半途反向（收起中显示/展开中收起）可从中间值续走。
    /// Height 属依赖动画（逐帧驱动布局），WinUI 默认禁用且静默跳过，须显式开启。
    private func addAnimation(
        to storyboard: Storyboard,
        target: FrameworkElement,
        property: String,
        to: Double,
        duration: Duration,
        easing: CubicEase,
        enablesDependentAnimation: Bool = false
    ) {
        let animation = DoubleAnimation()
        animation.to = to
        animation.duration = duration
        animation.easingFunction = easing
        animation.enableDependentAnimation = enablesDependentAnimation
        try? Storyboard.setTarget(animation, target)
        try? Storyboard.setTargetProperty(animation, property)
        storyboard.children.append(animation)
    }

    /// 二级页占满内容区；content 的显示与滚动由调用方决定——
    /// 自滚动控件（ItemsView/ScrollView 等）可直接传入，普通内容请自行包 ScrollView。
    public func navigateTo(label: UIElement, content: UIElement) {
        isMainShown = false

        ui.backButton.visibility = .visible
        ui.headerPanel.visibility = .collapsed
        ui.secondHeaderPanel.visibility = .visible
        ui.mainPanel.visibility = .collapsed
        ui.secondPanel.visibility = .visible

        ui.secondHeaderPanel.children.clear()
        ui.secondPanel.children.clear()
        ui.secondHeaderPanel.children.append(label)
        ui.secondPanel.children.append(content)

        try? ui.mainHiddenStoryboard.begin()
        try? ui.secondShownStoryboard.begin()
    }

    private func makeDuration(milliseconds: Int64) -> Duration {
        Duration(
            timeSpan: TimeSpan(duration: milliseconds * 10_000),
            type: .timeSpan
        )
    }
}

private var xamlUI: String {
    """
    <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        RowDefinitions ="Auto,*" ColumnDefinitions="*">
        <Grid.Resources>
            <ResourceDictionary>
                <Storyboard x:Name="MainShownStoryboard">
                    <DoubleAnimation Storyboard.TargetName="MainPanel" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="MainPanelTransform" Storyboard.TargetProperty="TranslateX" To="0" Duration="0:0:0.16" />
                </Storyboard>
                <Storyboard x:Name="MainHiddenStoryboard">
                    <DoubleAnimation Storyboard.TargetName="MainPanel" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.12" />
                    <DoubleAnimation Storyboard.TargetName="MainPanelTransform" Storyboard.TargetProperty="TranslateX" To="-12" Duration="0:0:0.12" />
                </Storyboard>
                <Storyboard x:Name="SecondShownStoryboard">
                    <DoubleAnimation Storyboard.TargetName="SecondPanel" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.16" />
                    <DoubleAnimation Storyboard.TargetName="SecondPanelTransform" Storyboard.TargetProperty="TranslateX" To="0" Duration="0:0:0.16" />
                </Storyboard>
                <Storyboard x:Name="SecondHiddenStoryboard">
                    <DoubleAnimation Storyboard.TargetName="SecondPanel" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.12" />
                    <DoubleAnimation Storyboard.TargetName="SecondPanelTransform" Storyboard.TargetProperty="TranslateX" To="12" Duration="0:0:0.12" />
                </Storyboard>
            </ResourceDictionary>
        </Grid.Resources>
        <Grid x:Name="HeaderGrid" Grid.Row="0" RowDefinitions="Auto" ColumnDefinitions="Auto,*,Auto">
            <AppBarButton x:Name="BackButton" Grid.Row="0" Grid.Column="0"
                Icon="Back" ToolTipService.ToolTip="{x:Tr Back}"
                AutomationProperties.Name="{x:Tr Back}" Visibility="Collapsed">
                <AppBarButton.Resources>
                <!-- The style can make button without padding and corner. -->
                <Style x:Key="IconOnlyAppBarButtonStyle" TargetType="AppBarButton">
                    <Setter Property="Width" Value="48"/>
                    <Setter Property="LabelPosition" Value="Collapsed"/>
                </Style>
                </AppBarButton.Resources>
                <AppBarButton.Style>
                    <StaticResource ResourceKey="IconOnlyAppBarButtonStyle"/>
                </AppBarButton.Style>
            </AppBarButton>
            <StackPanel x:Name="HeaderPanel" Grid.Row="0" Grid.Column="1"
                Orientation="Horizontal" HorizontalAlignment="Right">
            </StackPanel>
            <StackPanel x:Name="SecondHeaderPanel" Grid.Row="0" Grid.Column="2" Margin="0,0,16,0"
                Orientation="Horizontal" HorizontalAlignment="Right" Visibility="Collapsed">
            </StackPanel>
        </Grid>
        <ScrollView x:Name="MainScrollView" Grid.Row="1"
            VerticalAlignment="Stretch" HorizontalAlignment="Stretch" VerticalScrollBarVisibility="Auto">
            <Grid>
                <StackPanel x:Name="MainPanel" Padding="16,0,16,16" Spacing="16" HorizontalAlignment="Stretch" Opacity="1">
                    <StackPanel.RenderTransform>
                        <CompositeTransform x:Name="MainPanelTransform" />
                    </StackPanel.RenderTransform>
                </StackPanel>
            </Grid>
        </ScrollView>
        <!-- 二级页在 ScrollView 之外，占满内容区；内容的显示与滚动由调用方决定
             （自滚动控件直接传入，普通内容自行包 ScrollView）。 -->
        <Grid x:Name="SecondPanel" Grid.Row="1" Visibility="Collapsed" Opacity="0" Padding="16,0,16,16">
            <Grid.RenderTransform>
                <CompositeTransform x:Name="SecondPanelTransform" TranslateX="12" />
            </Grid.RenderTransform>
        </Grid>
    </Grid>
    """
}
