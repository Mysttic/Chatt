using Chatt.ViewModels;

namespace Chatt;

public partial class AppShell : Shell
{
	public AppShell()
	{
		InitializeComponent();
		this.BindingContext = new ShellViewModel(this);
	}

    private void ImageButton_Clicked(object sender, EventArgs e)
    {
		this.Window.Navigation.PopModalAsync();
    }
}
