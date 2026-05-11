"use client";

import { motion, useReducedMotion } from "framer-motion";
import {
  Smartphone,
  Monitor,
  Coffee,
  ExternalLink,
  Github,
  Download,
  Users,
  Star,
  ArrowRight,
  Linkedin,
} from "lucide-react";
import { Badge } from "~/components/ui/badge";

interface EcosystemProject {
  name: string;
  description: string;
  platform: string;
  icon: typeof Smartphone;
  link?: string;
  githubLink?: string;
  gradient: string;
  accentColor: string;
}

const projects: EcosystemProject[] = [
  {
    name: "IntuneBrew",
    description:
      "Streamline macOS app deployments with Homebrew integration. Perfect for managing Mac fleets in your Intune environment.",
    platform: "macOS",
    icon: Coffee,
    link: "https://IntuneBrew.com",
    gradient: "from-orange-500 to-red-500",
    accentColor:
      "text-orange-600 bg-orange-50 border-orange-200 dark:text-orange-400 dark:bg-orange-950/50 dark:border-orange-800/50",
  },
  {
    name: "IntuneGet",
    description:
      "Advanced Windows app management and deployment tools. Simplify your Windows device management workflow.",
    platform: "Windows",
    icon: Monitor,
    link: "https://IntuneGet.com",
    gradient: "from-blue-500 to-cyan-500",
    accentColor:
      "text-blue-600 bg-blue-50 border-blue-200 dark:text-blue-400 dark:bg-blue-950/50 dark:border-blue-800/50",
  },
  {
    name: "IntuneRemote",
    description:
      "Mobile companion app for on-the-go Intune management. Monitor and control your device fleet from anywhere.",
    platform: "iOS & Android",
    icon: Smartphone,
    link: "https://IntuneRemote.com",
    gradient: "from-purple-500 to-pink-500",
    accentColor:
      "text-purple-600 bg-purple-50 border-purple-200 dark:text-purple-400 dark:bg-purple-950/50 dark:border-purple-800/50",
  },
];

const statusColors = {
  stable:
    "text-green-600 bg-green-50 border-green-200 dark:text-green-400 dark:bg-green-950/50 dark:border-green-800/50",
  beta: "text-yellow-600 bg-yellow-50 border-yellow-200 dark:text-yellow-400 dark:bg-yellow-950/50 dark:border-yellow-800/50",
  "coming-soon":
    "text-gray-600 bg-gray-50 border-gray-200 dark:text-gray-400 dark:bg-gray-950/50 dark:border-gray-800/50",
};

// Moved outside the component to prevent recreation on each render
const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.2,
      delayChildren: 0.1,
    },
  },
};

// Simpler static cardVariants (common approach):
const staticCardVariants = {
  hidden: {
    opacity: 0,
    y: 30, // Default y for animation
    scale: 0.95, // Default scale for animation
  },
  visible: {
    opacity: 1,
    y: 0,
    scale: 1,
    transition: {
      type: "spring",
      damping: 20,
      stiffness: 300,
    },
  },
};

export default function EcosystemSection() {
  const prefersReducedMotion = useReducedMotion();

  return (
    <section className="relative overflow-hidden px-4 py-24">
      {/* Background Elements */}
      <div className="absolute inset-0 z-0" aria-hidden="true">
        <div className="from-background/50 via-background/80 to-background absolute inset-0 bg-gradient-to-b"></div>
        {!prefersReducedMotion && (
          <>
            <motion.div
              className="absolute top-1/3 right-1/4 h-64 w-64 rounded-full bg-blue-500/5 blur-3xl"
              animate={{
                scale: [1, 1.2, 1],
                opacity: [0.3, 0.5, 0.3],
              }}
              transition={{
                duration: 8,
                repeat: Number.POSITIVE_INFINITY,
                ease: "easeInOut",
              }}
            />
            <motion.div
              className="absolute bottom-1/3 left-1/4 h-64 w-64 rounded-full bg-purple-500/5 blur-3xl"
              animate={{
                scale: [1.2, 1, 1.2],
                opacity: [0.5, 0.3, 0.5],
              }}
              transition={{
                duration: 8,
                repeat: Number.POSITIVE_INFINITY,
                ease: "easeInOut",
                delay: 4,
              }}
            />
          </>
        )}
      </div>

      <div className="relative z-10 mx-auto max-w-7xl">
        {/* Section Header */}
        <motion.div
          className="mb-16 text-center"
          initial={{ opacity: 0, y: prefersReducedMotion ? 0 : 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8 }}
        >
          <h2 className="mb-4 text-4xl font-bold md:text-5xl">
            <span className="bg-gradient-to-r from-blue-600 via-purple-600 to-blue-600 bg-clip-text text-transparent">
              Other Tools and Projects
            </span>
          </h2>
          <p className="text-muted-foreground mx-auto max-w-3xl text-xl">
            Here are some of the open-source tools I've built to help make
            Intune easier.
          </p>
        </motion.div>

        {/* Projects Grid */}
        <motion.div
          className="grid grid-cols-1 gap-8 md:grid-cols-2 lg:grid-cols-3"
          variants={containerVariants}
          initial="hidden"
          animate="visible"
        >
          {projects.map((project, index) => {
            const IconComponent = project.icon;

            return (
              <motion.div
                key={project.name}
                variants={staticCardVariants}
                initial={
                  prefersReducedMotion
                    ? { opacity: 1, y: 0, scale: 1 }
                    : "hidden"
                }
                animate="visible"
                className="group"
              >
                <div className="bg-card hover:border-primary/20 relative flex h-full flex-col overflow-hidden rounded-2xl border p-6 text-left shadow-sm transition-all duration-300 hover:shadow-xl">
                  {/* Background gradient overlay */}
                  <div
                    className={`absolute inset-0 bg-gradient-to-br ${project.gradient} opacity-0 transition-all duration-500 group-hover:opacity-5`}
                  />

                  {/* Content */}
                  <div className="relative z-10 flex h-full flex-col">
                    {/* Header */}
                    <div className="mb-4 flex items-start justify-between">
                      <div className="flex items-start gap-3">
                        <div
                          className={`rounded-xl p-2.5 transition-all duration-300 group-hover:scale-110 ${project.accentColor}`}
                        >
                          <IconComponent className="h-6 w-6" />
                        </div>
                        <div className="text-left">
                          <h3 className="group-hover:text-primary text-xl font-bold transition-colors duration-300">
                            {project.name}
                          </h3>
                          <p className="text-muted-foreground text-sm">
                            {project.platform}
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* Description */}
                    <p className="text-muted-foreground mb-4 text-sm leading-relaxed">
                      {project.description}
                    </p>

                    {/* Action Buttons */}
                    <div className="mt-auto flex gap-2">
                      {project.link && (
                        <motion.a
                          href={project.link}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="group/btn flex flex-1 items-center justify-center gap-2 rounded-lg bg-gradient-to-r from-blue-500 to-purple-600 px-4 py-2 text-sm font-medium text-white transition-all duration-300 hover:from-blue-600 hover:to-purple-700"
                          onClick={() => {
                            if (
                              typeof window !== "undefined" &&
                              (window as any).plausible
                            ) {
                              (window as any).plausible("Project Click", {
                                props: {
                                  project: project.name,
                                  platform: project.platform,
                                  destination: project.link,
                                },
                              });
                            }
                          }}
                          whileHover={
                            prefersReducedMotion ? {} : { scale: 1.02 }
                          }
                          whileTap={prefersReducedMotion ? {} : { scale: 0.98 }}
                        >
                          <span>Visit Site</span>{" "}
                          <ExternalLink className="h-3 w-3 transition-transform group-hover/btn:translate-x-0.5" />
                        </motion.a>
                      )}
                      {project.githubLink && (
                        <motion.a
                          href={project.githubLink}
                          target="_blank"
                          rel="noopener noreferrer"
                          className={`${project.link ? "px-3" : "flex-1 px-4"} border-border/50 hover:bg-secondary/50 group/btn flex items-center justify-center gap-2 rounded-lg border py-2 text-sm font-medium transition-all duration-300`}
                          whileHover={
                            prefersReducedMotion ? {} : { scale: 1.02 }
                          }
                          whileTap={prefersReducedMotion ? {} : { scale: 0.98 }}
                        >
                          {project.link ? (
                            <Github className="h-4 w-4" />
                          ) : (
                            <>
                              <Github className="h-3 w-3" />
                              <span>View Source</span>
                              <ArrowRight className="h-3 w-3 transition-transform group-hover/btn:translate-x-0.5" />
                            </>
                          )}
                        </motion.a>
                      )}
                    </div>
                  </div>

                  {/* Hover glow effect */}
                  <div
                    className={`absolute -inset-1 -z-10 rounded-2xl bg-gradient-to-r ${project.gradient} opacity-0 blur-sm transition-opacity duration-500 group-hover:opacity-20`}
                  />
                </div>
              </motion.div>
            );
          })}
        </motion.div>

        {/* Call to Action */}
        <motion.div
          className="mt-16 text-center"
          initial={{ opacity: 0, y: prefersReducedMotion ? 0 : 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.5 }}
        >
          <p className="text-muted-foreground mb-6">
            Building the future of Intune automation, one tool at a time.
          </p>
          <div className="flex flex-col items-center justify-center gap-4 sm:flex-row">
            <motion.a
              href="https://github.com/ugurkocde"
              target="_blank"
              rel="noopener noreferrer"
              className="bg-secondary/50 text-secondary-foreground hover:bg-secondary/70 border-secondary/20 focus:ring-secondary inline-flex items-center gap-2 rounded-2xl border px-6 py-3 font-medium backdrop-blur-sm transition-all duration-300 focus:ring-2 focus:ring-offset-2 focus:outline-none"
              onClick={() => {
                if (
                  typeof window !== "undefined" &&
                  (window as any).plausible
                ) {
                  (window as any).plausible("Social Click", {
                    props: {
                      platform: "GitHub",
                      location: "ecosystem-section",
                    },
                  });
                }
              }}
              whileHover={prefersReducedMotion ? {} : { scale: 1.05, y: -2 }}
              whileTap={prefersReducedMotion ? {} : { scale: 0.95 }}
            >
              <Github className="h-4 w-4" />
              Follow for Updates
              <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
            </motion.a>
            <motion.a
              href="https://www.linkedin.com/in/ugurkocde" // 👈 UPDATE: Replace with your actual LinkedIn profile URL
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-2xl bg-blue-600/90 px-6 py-3 font-medium text-white transition-all duration-300 hover:bg-blue-700 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:outline-none"
              onClick={() => {
                if (
                  typeof window !== "undefined" &&
                  (window as any).plausible
                ) {
                  (window as any).plausible("Social Click", {
                    props: {
                      platform: "LinkedIn",
                      location: "ecosystem-section",
                    },
                  });
                }
              }}
              whileHover={prefersReducedMotion ? {} : { scale: 1.05, y: -2 }}
              whileTap={prefersReducedMotion ? {} : { scale: 0.95 }}
            >
              <Linkedin className="h-4 w-4" />
              Follow on LinkedIn
              <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
            </motion.a>
          </div>
        </motion.div>
      </div>
    </section>
  );
}
