import WinUI

public class SettingsGroup: StackPanel {

    // MARK: - Public properties

    public let title: String
    /// Whether the group's cards are shown. Defaults to `true`; assigning a new
    /// value expands or collapses the group with the same animation as the toggle button.
    public var isExpanded: Bool {
        didSet {
            guard isExpanded != oldValue else { return }
            runExpandCollapseAnimation(expanding: isExpanded)
        }
    }

    public let expand = EventWithArgumentHandler<SettingsGroup, Bool>()

    // MARK: - Private state

    private let ui:
        (
            titleLabel: TextBlock,
            toggleButton: AppBarButton,
            headerGrid: Grid,
            chevronTransform: CompositeTransform,
            cardsHost: StackPanel,
            cardsHostTransform: CompositeTransform,
            expandStoryboard: Storyboard,
            collapseStoryboard: Storyboard
        )
    private let isExpandable: Bool
    private var isAnimating = false

    // MARK: - Init

    public init(title: String, cards: [WinUI.UIElement], isExpandable: Bool = true, isExpanded: Bool = true) {
        self.title = title
        self.isExpanded = isExpanded
        self.isExpandable = isExpandable

        let loaded: Grid = App.context.requireXaml(withString: xamlUI)
        ui = (
            titleLabel: loaded.requireElement("TitleLabel"),
            toggleButton: loaded.requireElement("ToggleButton"),
            headerGrid: loaded.requireElement("HeaderGrid"),
            chevronTransform: loaded.requireElement("ChevronTransform"),
            cardsHost: loaded.requireElement("CardsHost"),
            cardsHostTransform: loaded.requireElement("CardsHostTransform"),
            expandStoryboard: loaded.requireResource("ExpandStoryboard"),
            collapseStoryboard: loaded.requireResource("CollapseStoryboard")
        )
        ui.titleLabel.text = title
        ui.toggleButton.visibility = isExpandable ? .visible : .collapsed
        for card in cards {
            ui.cardsHost.children.append(card)
        }

        super.init()
        self.children.append(loaded)

        // Chevron-down (0°) means collapsible, chevron-up (180°) means expanded —
        // same convention as SettingsExpander. Snapped without animation for the initial state.
        if isExpanded {
            ui.chevronTransform.rotation = 180
        } else {
            ui.cardsHost.visibility = .collapsed
            ui.cardsHost.opacity = 0
            ui.cardsHostTransform.translateY = -8
        }

        ui.toggleButton.click.addHandler { [weak self] _, _ in
            self?.toggleExpanded()
        }
        // A single click on the chevron triggers both the button's `click` and the header's
        // `tapped` (AppBarButton does not swallow pointer events); `toggleExpanded()` ignores
        // the second call so one physical click toggles exactly once.
        ui.headerGrid.tapped.addHandler { [weak self] _, _ in
            guard let self, self.isExpandable else { return }
            self.toggleExpanded()
        }
        // The storyboards are reused across runs, so completed handlers are wired once here.
        ui.expandStoryboard.completed.addHandler { [weak self] _, _ in
            self?.isAnimating = false
        }
        ui.collapseStoryboard.completed.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.ui.cardsHost.visibility = .collapsed
            self.isAnimating = false
        }
    }

    /// Ignored while an expand/collapse animation is running: this both collapses the
    /// click + tapped pair of one physical interaction into a single toggle, and coherently
    /// debounces rapid re-clicks (instead of flipping the state without an animation).
    private func toggleExpanded() {
        guard !isAnimating else { return }

        isExpanded = !isExpanded
        expand.invoke(self, isExpanded)
    }

    private func runExpandCollapseAnimation(expanding: Bool) {
        guard !isAnimating else { return }
        isAnimating = true

        if expanding {
            ui.cardsHost.visibility = .visible
            ui.cardsHost.opacity = 0
            ui.cardsHostTransform.translateY = -8
        }

        try? (expanding ? ui.expandStoryboard : ui.collapseStoryboard).begin()
    }
}

private var xamlUI: String {
    """
    <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        RowDefinitions="Auto,Auto">
        <Grid.Resources>
            <ResourceDictionary>
                <Storyboard x:Name="ExpandStoryboard">
                    <DoubleAnimation Storyboard.TargetName="CardsHost" Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.333">
                        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                    </DoubleAnimation>
                    <DoubleAnimation Storyboard.TargetName="CardsHostTransform" Storyboard.TargetProperty="TranslateY" From="-8" To="0" Duration="0:0:0.333">
                        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                    </DoubleAnimation>
                    <DoubleAnimation Storyboard.TargetName="ChevronTransform" Storyboard.TargetProperty="Rotation" From="0" To="180" Duration="0:0:0.333">
                        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                    </DoubleAnimation>
                </Storyboard>
                <Storyboard x:Name="CollapseStoryboard">
                    <DoubleAnimation Storyboard.TargetName="CardsHost" Storyboard.TargetProperty="Opacity" From="1" To="0" Duration="0:0:0.133">
                        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseIn"/></DoubleAnimation.EasingFunction>
                    </DoubleAnimation>
                    <DoubleAnimation Storyboard.TargetName="CardsHostTransform" Storyboard.TargetProperty="TranslateY" From="0" To="-8" Duration="0:0:0.133">
                        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseIn"/></DoubleAnimation.EasingFunction>
                    </DoubleAnimation>
                    <DoubleAnimation Storyboard.TargetName="ChevronTransform" Storyboard.TargetProperty="Rotation" From="180" To="0" Duration="0:0:0.133">
                        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseIn"/></DoubleAnimation.EasingFunction>
                    </DoubleAnimation>
                </Storyboard>
            </ResourceDictionary>
        </Grid.Resources>
        <Grid Name="HeaderGrid" Grid.Row="0" ColumnDefinitions="*,Auto">
            <TextBlock Name="TitleLabel" Grid.Column="0"
                Style="{StaticResource BodyStrongTextBlockStyle}" VerticalAlignment="Center"/>
            <AppBarButton Name="ToggleButton" Grid.Column="1"
                Width="40" LabelPosition="Collapsed">
                <AppBarButton.Icon>
                    <FontIcon Glyph="&#xE70D;" RenderTransformOrigin="0.5,0.5">
                        <FontIcon.RenderTransform>
                            <CompositeTransform Name="ChevronTransform"/>
                        </FontIcon.RenderTransform>
                    </FontIcon>
                </AppBarButton.Icon>
            </AppBarButton>
        </Grid>
        <StackPanel Name="CardsHost" Grid.Row="1" Orientation="Vertical" Spacing="4">
            <StackPanel.RenderTransform>
                <CompositeTransform Name="CardsHostTransform"/>
            </StackPanel.RenderTransform>
        </StackPanel>
    </Grid>
    """
}
