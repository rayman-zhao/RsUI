import WinUI
import WindowsFoundation

open class SettingsPanel: WinUI.Grid {
    private let ui:
        (
            root: Grid,
            backButton: Button,
            headerPanel: StackPanel,
            secondHeaderPanel: StackPanel,

            mainScrollView: ScrollView,
            mainPanel: StackPanel,
            secondPanel: StackPanel,

            mainShownStoryboard: Storyboard,
            mainHiddenStoryboard: Storyboard,
            secondShownStoryboard: Storyboard,
            secondHiddenStoryboard: Storyboard,
        )

    public override init() {
        let loaded: Grid = App.context.requireXaml(withString: xamlUI)
        ui = (
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
            secondHiddenStoryboard: loaded.requireResource("SecondHiddenStoryboard"),
        )

        super.init()
        children.append(ui.root)

        ui.backButton.click.addHandler { [weak self] _, _ in
            guard let self else { return }

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

    public func append(icon: WinUI.IconElement?, label: String, card: UIElement) {
        if let icon {
            let button: AppBarButton = App.context.requireXaml(withString: xamlAppBarButton.replacingOccurrences(of: "{x:ToolTip}", with: label))
            button.icon = icon
            button.click.addHandler { [weak self] _, _ in
                guard
                    let self,
                    let transform = try? card.transformToVisual(ui.mainScrollView),
                    let point = try? transform.transformPoint(.init(x: 0, y: 0))
                else { return }

                let offset = min(self.ui.mainScrollView.scrollableHeight, max(0.0, Double(point.y) - 28.0))
                _ = try? self.ui.mainScrollView.scrollTo(0, Double(offset))
            }
            ui.headerPanel.children.append(button)
        }

        ui.mainPanel.children.append(SettingsGroup(label, [card]))
    }

    public func navigateTo(label: UIElement, card: UIElement) {
        ui.backButton.visibility = .visible
        ui.headerPanel.visibility = .collapsed
        ui.secondHeaderPanel.visibility = .visible
        ui.mainPanel.visibility = .collapsed
        ui.secondPanel.visibility = .visible

        ui.secondHeaderPanel.children.append(label)
        ui.secondPanel.children.append(card)

        try? ui.mainHiddenStoryboard.begin()
        try? ui.secondShownStoryboard.begin()
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
                Icon="Back" ToolTipService.ToolTip="{x:Tr Back}" Visibility="Collapsed">
                <AppBarButton.Resources>
                <!-- The style can make button without padding and corner. -->
                <Style x:Key="ViewerChromeAppBarButtonStyle" TargetType="AppBarButton">
                    <Setter Property="Width" Value="48"/>
                    <Setter Property="LabelPosition" Value="Collapsed"/>
                </Style>
                </AppBarButton.Resources>
                <AppBarButton.Style>
                    <StaticResource ResourceKey="ViewerChromeAppBarButtonStyle"/>
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
                <StackPanel x:Name="MainPanel" Padding="16,0,16,0" Spacing="16" HorizontalAlignment="Stretch" Opacity="1">
                    <StackPanel.RenderTransform>
                        <CompositeTransform x:Name="MainPanelTransform" />
                    </StackPanel.RenderTransform>
                </StackPanel>
                <StackPanel x:Name="SecondPanel" Visibility="Collapsed" Opacity="0" Padding="16,0,16,0" Spacing="16">
                    <StackPanel.RenderTransform>
                        <CompositeTransform x:Name="SecondPanelTransform" TranslateX="12" />
                    </StackPanel.RenderTransform>
                </StackPanel>
            </Grid>
        </ScrollView>
    </Grid>
    """
}

private var xamlAppBarButton: String {
    """
    <AppBarButton xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        ToolTipService.ToolTip="{x:ToolTip}">
        <AppBarButton.Resources>
        <!-- The style can make button without padding and corner. -->
        <Style x:Key="ViewerChromeAppBarButtonStyle" TargetType="AppBarButton">
            <Setter Property="Width" Value="48"/>
            <Setter Property="LabelPosition" Value="Collapsed"/>
        </Style>
        </AppBarButton.Resources>
        <AppBarButton.Style>
            <StaticResource ResourceKey="ViewerChromeAppBarButtonStyle"/>
        </AppBarButton.Style>
    </AppBarButton>
    """
}
