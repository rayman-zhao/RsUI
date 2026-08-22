import Foundation
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

        let centerText = TextBlock()
        centerText.text = tr("Viewer center content")
        centerText.horizontalAlignment = .center
        centerText.verticalAlignment = .center
        viewer.centerContent = centerText

        let loaded = (try? XamlReader.load(xamlUI)) as! Grid
        let fsbtn = (try? loaded.findName("FullscreenButton")) as! Button
        fsbtn.click.addHandler { [weak self] _, _ in
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

        let rightText = TextBlock()
        rightText.text = tr("Viewer right pane")
        rightText.horizontalAlignment = .center
        rightText.verticalAlignment = .center
        viewer.rightContent = rightText

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
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
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
            <TextBlock x:Name="TopHost" Grid.Column="0" Text="The Viewer Toolbar" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <AppBarButton x:Name="FullscreenButton" Icon="Fullscreen" Grid.Column="1" Style="{StaticResource ViewerChromeAppBarButtonStyle}">
            </AppBarButton>
        </Grid>
        """
    }
}
