import { type Script } from "~/lib/scripts";
import {
  BreadcrumbSchema,
  SoftwareSourceCodeSchema,
} from "~/components/structured-data";
import { ScriptDetailPage } from "./script-detail-page";

interface ScriptDetailPageWrapperProps {
  script: Script;
  allScripts?: Script[];
  permissionsData?: Record<
    string,
    { displayName: string; description: string }
  >;
}

export function ScriptDetailPageWrapper({
  script,
  allScripts,
  permissionsData,
}: ScriptDetailPageWrapperProps) {
  const baseUrl = "https://intuneautomation.com";

  const breadcrumbItems = [
    { name: "Home", url: "/" },
    { name: "Scripts", url: "/scripts" },
    { name: script.title },
  ];

  return (
    <>
      <BreadcrumbSchema baseUrl={baseUrl} items={breadcrumbItems} />
      <SoftwareSourceCodeSchema script={script} baseUrl={baseUrl} />
      <ScriptDetailPage
        script={script}
        allScripts={allScripts}
        permissionsData={permissionsData}
      />
    </>
  );
}
