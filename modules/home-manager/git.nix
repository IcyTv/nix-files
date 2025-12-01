{ ... }:
{
  programs.git = {
    enable = true;
    settings = {
      init = {
	defaultBranch = "main";
      };

      user = {
	name = "Michael Finger";
	email = "michael.finger@icytv.de";
      };

      url = {
	"https://github.com/" = {
	  insteadOf = [
	    "gh:"
	    "github:"
	  ];
	};
      };

    };
  };
}
