using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Configuration;

namespace WebApplication1.Controllers
{
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            ViewBag.Environment = ConfigurationManager.AppSettings["Environment"];
            ViewBag.ReleaseNumber = ConfigurationManager.AppSettings["OctopusReleaseNumber"];
            ViewBag.DeploymentNumber = ConfigurationManager.AppSettings["OctopusDeploymentId"];
      
            var mvcName = typeof(Controller).Assembly.GetName();
            var isMono = Type.GetType("Mono.Runtime") != null;

            ViewBag.MvcVersion = mvcName.Version.Major + "." + mvcName.Version.Minor;
            ViewBag.Runtime = isMono ? "Mono" : ".NET";

            return View();
        }

        public ActionResult About()
        {
            ViewBag.Message = "Your application description page.";

            return View();
        }

        public ActionResult Contact()
        {
            ViewBag.Message = "Your contact page.";

            return View();
        }
    }
}