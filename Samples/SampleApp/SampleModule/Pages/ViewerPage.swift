import Foundation
import RsFoundation
import RsUI
import UWP
import WinUI

final class ViewerPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://sample/viewer")! }
    var title: String { tr("Viewer") }

    var content: WinUI.UIElement {
        let viewer = Viewer()

        let border = Border()
        border.background = WinUI.SolidColorBrush(UWP.Color(a: 0xff, r: 0xff, g: 0x00, b: 0x00))
        let centerText = TextBlock()
        centerText.text = tr("Viewer center content")

        centerText.horizontalAlignment = .center
        centerText.verticalAlignment = .center
        border.child = centerText
        viewer.centerContent = border

        guard let loaded = (try? XamlReader.load(App.context.tr(xaml: xamlUI))) as? Grid else {
            log.warning("ViewerPage: failed to load viewer chrome XAML")
            return viewer
        }
        let fsbtn = (try? loaded.findName("FullscreenButton")) as? Button
        fsbtn?.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            if self.context.isInFullscreen {
                self.context.exitFullscreen()
            } else {
                self.context.enterFullscreen()
            }
        }
        viewer.topContent = loaded

        let leftText = TextBlock()
        leftText.text = tr("Viewer left pane")
        leftText.horizontalAlignment = .center
        leftText.verticalAlignment = .center
        viewer.leftContent = leftText

        let rightPane = SettingsPanel()
        for i in 0..<8 {
            let title = String(format: tr("Group %d"), Int32(i))
            let card = SettingsCard(header: title)
            card.isClickEnabled = true
            card.click.addHandler { _, _ in
                let l = TextBlock()
                l.verticalAlignment = .center
                l.text = title

                // 二级页不提供滚动，显示与滚动方式由 client 决定：
                // 首组演示自滚动控件（GridView 内部是 ItemsView）直接传入，
                // 其余组演示普通内容自行包 ScrollView。
                let content: UIElement
                if i == 0 {
                    let gridView = RsUI.GridView()
                    gridView.setItems((0..<60).map { String(format: tr("Snapshot %d"), Int32($0)) })
                    content = gridView
                } else {
                    let scroller = ScrollView()
                    let listPanel = StackPanel()
                    listPanel.spacing = 16
                    for j in 0..<20 {
                        listPanel.children.append(
                            SettingsCard(header: String(format: tr("Second Item %d"), Int32(j))))
                    }
                    scroller.content = listPanel
                    content = scroller
                }

                rightPane.navigateTo(label: l, content: content)
            }
            let card2 = SettingsCard(header: String(format: tr("Group %d Not Clickable"), Int32(i)))
            rightPane.append(glyph: "\u{F0E3}", title: title, cards: [card, card2])
        }

        viewer.rightContent = rightPane

        let bottomText = TextBlock()
        bottomText.text = tr("Viewer bottom pane")
        bottomText.horizontalAlignment = .center
        bottomText.verticalAlignment = .center
        viewer.bottomContent = bottomText

        return viewer
    }

    private var xamlUI: String {
        """
        <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Background="Blue">
            <Grid.Resources>
                <ResourceDictionary>
                    <Style x:Key="ViewerChromeAppBarButtonStyle" TargetType="AppBarButton">
                        <Setter Property="Width" Value="48"/>
                        <Setter Property="LabelPosition" Value="Collapsed" />
                    </Style>
                </ResourceDictionary>
            </Grid.Resources>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="TopHost" Grid.Column="0" Text="{x:Tr The Viewer Toolbar}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <AppBarButton x:Name="FullscreenButton" Icon="Fullscreen" Grid.Column="1" Style="{StaticResource ViewerChromeAppBarButtonStyle}">
            </AppBarButton>
        </Grid>
        """
    }
}
