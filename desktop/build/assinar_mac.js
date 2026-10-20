// No Mac, o programa precisa de uma assinatura (mesmo que local, "ad hoc") para
// abrir em computadores com chip Apple. Sem certificado da Apple, assina assim.
const { execFileSync } = require("child_process");
const path = require("path");

exports.default = async function (contexto) {
  if (contexto.electronPlatformName !== "darwin") return;
  const appPath = path.join(contexto.appOutDir, `${contexto.packager.appInfo.productFilename}.app`);
  console.log(`Assinatura ad hoc: ${appPath}`);
  execFileSync("codesign", ["--force", "--deep", "--sign", "-", appPath], { stdio: "inherit" });
};
